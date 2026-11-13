// Isolated-world bridge between the page hook (inject.js) and the service
// worker. The service worker learns the page origin from the port sender,
// so the page cannot claim another website's identity.
(() => {
  "use strict";
  let pagePort = null;
  let runtimePort = null;
  let pluginUsed = false;

  function runtime() {
    if (runtimePort) return runtimePort;
    runtimePort = chrome.runtime.connect({ name: "magic-sign" });
    runtimePort.onMessage.addListener((message) => pagePort?.postMessage(message));
    runtimePort.onDisconnect.addListener(() => {
      runtimePort = null;
    });
    return runtimePort;
  }

  let debugTimer = null;

  /** Same rules as the server: exact origin, `https://*.example.vn` or `*`. */
  function originAllowed(origin, patterns) {
    return (patterns || []).some((pattern) => {
      if (pattern === "*" || pattern.toLowerCase() === origin.toLowerCase()) return true;
      const match = pattern.match(/^(https?):\/\/\*\.(.+)$/i);
      if (!match) return false;
      const host = location.hostname.toLowerCase();
      const suffix = match[2].toLowerCase();
      return location.protocol === `${match[1].toLowerCase()}:` && (host === suffix || host.endsWith(`.${suffix}`));
    });
  }

  async function sendConfig() {
    if (!pagePort) return;
    const { enabled = true, ports = [], debug } = await chrome.storage.local.get(["enabled", "ports", "debug"]);
    const until = debug?.until ? Date.parse(debug.until) : 0;
    const logging = until > Date.now() && originAllowed(location.origin, debug.origins);
    clearTimeout(debugTimer);
    if (logging) debugTimer = setTimeout(sendConfig, Math.min(until - Date.now() + 50, 2 ** 31 - 1));
    pagePort.postMessage({ t: "config", enabled, ports, debug: logging });
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.__magicSign !== "init" || !event.ports[0]) return;
    pagePort = event.ports[0];
    pagePort.onmessage = (message) => {
      if (message.data?.t === "plugin_used") {
        pluginUsed = true;
        return;
      }
      try {
        runtime().postMessage(message.data);
      } catch {
        // The service worker restarted; reconnect once and retry.
        runtimePort = null;
        runtime().postMessage(message.data);
      }
    };
    void sendConfig();
  });

  // A sign server's web app asks for the extension state or to connect this
  // browser. The service worker reads the origin from the message sender.
  window.addEventListener("message", (event) => {
    const request = event.data?.__magicSignWeb;
    const types = { status: "web_status", connect: "web_connect", relay_status: "relay_status", relay_connect: "relay_connect" };
    if (event.source !== window || !types[request]) return;
    const rid = event.data.rid;
    const { agentId, invite, deviceName } = event.data;
    chrome.runtime
      .sendMessage({ t: types[request], agentId, invite, deviceName })
      .catch((error) => ({ ok: false, error: error.message }))
      .then((result) => window.postMessage({ __magicSignWeb: "reply", rid, ...result }, location.origin));
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    // Plugin connections already open keep their old route; reload the pages
    // that used the plugin so the switch takes effect.
    const flipped = changes.enabled && (changes.enabled.oldValue !== false) !== (changes.enabled.newValue !== false);
    if (flipped && pluginUsed) {
      location.reload();
      return;
    }
    if (changes.enabled || changes.ports || changes.debug) void sendConfig();
  });

  window.postMessage({ __magicSign: "bridge-ready" }, "*");
})();
