// Bridge between the page hook (inject.js) and the app, in every website the
// app opens. Same job as the extension's bridge.js, but the other end is the
// Flutter host through the `MagicSignNative` web message listener. The app
// learns the frame origin from the WebView itself, not from this script.
(() => {
  "use strict";
  if (window.__magicSignBridge) return;
  window.__magicSignBridge = true;

  // Random per frame: only this frame can read the replies addressed to it.
  const fid = Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, "0")).join("");
  let pagePort = null;
  let pluginUsed = false;
  let config = { enabled: true, ports: [], debug: null };
  let debugTimer = null;
  const webWaiters = new Map();

  // iOS adds the listener object after the app's own document-start scripts:
  // queue until it shows up.
  let native = null;
  const outbox = [];
  const post = (message) => {
    const data = JSON.stringify({ fid, ...message });
    if (native) native.postMessage(data);
    else outbox.push(data);
  };
  (function attach(tries) {
    if (!window.MagicSignNative) {
      if (tries < 300) setTimeout(() => attach(tries + 1), 10);
      return;
    }
    native = window.MagicSignNative;
    native.addEventListener("message", onNative);
    outbox.splice(0).forEach((data) => native.postMessage(data));
  })(0);

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

  function sendConfig() {
    if (!pagePort) return;
    const { enabled, ports, debug } = config;
    const until = debug?.until ? Date.parse(debug.until) : 0;
    const logging = until > Date.now() && originAllowed(location.origin, debug.origins);
    clearTimeout(debugTimer);
    if (logging) debugTimer = setTimeout(sendConfig, Math.min(until - Date.now() + 50, 2 ** 31 - 1));
    pagePort.postMessage({ t: "config", enabled, ports, debug: logging });
  }

  function onNative(event) {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      return;
    }
    // Android answers this frame only; iOS answers the main frame.
    if (message.fid && message.fid !== fid) return;
    switch (message.k) {
      case "config": {
        const flipped = message.config.enabled !== config.enabled;
        config = message.config;
        // Plugin connections already open keep their old route; reload the
        // pages that used the plugin so the switch takes effect.
        if (flipped && pluginUsed && message.changed) {
          location.reload();
          return;
        }
        sendConfig();
        break;
      }
      case "port":
        pagePort?.postMessage(message.message);
        break;
      case "web": {
        const resolve = webWaiters.get(message.rid);
        webWaiters.delete(message.rid);
        resolve?.(message.result || { ok: false, error: "Không có phản hồi" });
        break;
      }
    }
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.__magicSign !== "init" || !event.ports[0]) return;
    pagePort = event.ports[0];
    pagePort.onmessage = (message) => {
      if (message.data?.t === "plugin_used") {
        pluginUsed = true;
        return;
      }
      post({ k: "port", message: message.data });
    };
    sendConfig();
  });

  // A sign server's web app or the connect page asks for the app state or to
  // connect. The app reads the origin from the WebView.
  window.addEventListener("message", (event) => {
    const request = event.data?.__magicSignWeb;
    const types = { status: "web_status", connect: "web_connect", relay_status: "relay_status", relay_connect: "relay_connect" };
    if (event.source !== window || !types[request]) return;
    const rid = event.data.rid;
    const { agentId, invite, deviceName } = event.data;
    const wid = `${Date.now()}-${Math.random()}`;
    new Promise((resolve) => {
      webWaiters.set(wid, resolve);
      post({ k: "web", rid: wid, message: { t: types[request], agentId, invite, deviceName } });
    }).then((result) => window.postMessage({ __magicSignWeb: "reply", rid, ...result }, location.origin));
  });

  post({ k: "hello" });
  window.postMessage({ __magicSign: "bridge-ready" }, "*");
})();
