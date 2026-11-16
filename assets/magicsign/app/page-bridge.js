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

  // iOS / macOS deliver every native reply to the main frame. The main frame
  // hands replies addressed to another frame on to its same-origin
  // descendants (they can already script each other); a cross-origin frame
  // gets nothing, as before. Android and Windows answer the right frame.
  const FORWARD = "__magicSignNativeForward";
  function forwardToFrames(data) {
    const visit = (win) => {
      for (let index = 0; index < win.frames.length; index++) {
        const child = win.frames[index];
        try {
          if (child.location.origin !== location.origin) continue;
        } catch {
          continue;
        }
        child.postMessage({ [FORWARD]: data }, location.origin);
        visit(child);
      }
    };
    visit(window);
  }
  if (window.top !== window) {
    window.addEventListener("message", (event) => {
      if (event.origin !== location.origin || event.source !== window.top || typeof event.data?.[FORWARD] !== "string") return;
      onNative({ data: event.data[FORWARD] });
    });
  }

  // Diagnostics for kyso-trace.log: what reached this frame and the page's
  // own script errors once it talks to a plugin. Short text only: message
  // kinds, error messages and script paths, never payloads or page content.
  let traces = 0;
  const trace = (e) => {
    if (traces++ < 100) post({ k: "trace", e: String(e).slice(0, 240) });
  };
  const where = (file, line) => {
    try {
      const url = new URL(file);
      return ` @ ${url.origin}${url.pathname}:${line ?? "?"}`;
    } catch {
      return file ? ` @ ${String(file).split("?")[0]}:${line ?? "?"}` : "";
    }
  };
  window.addEventListener("error", (event) => {
    if (pluginUsed) trace(`lỗi JS: ${event.message}${where(event.filename, event.lineno)}`);
  });
  window.addEventListener("unhandledrejection", (event) => {
    if (pluginUsed) trace(`promise lỗi: ${event.reason?.message ?? event.reason}`);
  });

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

  // iOS / macOS send base64 ("b64:..."): the plugin quotes the reply into a
  // JS string without escaping backslashes, which breaks any JSON inside.
  function decodeNative(data) {
    if (typeof data !== "string" || !data.startsWith("b64:")) return data;
    return new TextDecoder().decode(Uint8Array.from(atob(data.slice(4)), (c) => c.charCodeAt(0)));
  }

  function onNative(event) {
    let message;
    try {
      message = JSON.parse(decodeNative(event.data));
    } catch (error) {
      trace(`tin từ app hỏng (${typeof event.data}, ${String(event.data ?? "").length}B): ${error?.message ?? error}`);
      return;
    }
    // Android answers this frame only; iOS answers the main frame.
    if (message.fid && message.fid !== fid) {
      if (window.top === window) forwardToFrames(event.data);
      return;
    }
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
      case "port": {
        const t = message.message?.t;
        if (t && t !== "log") {
          pluginUsed = true;
          trace(`nhận ${t} #${message.message.id ?? ""}${pagePort ? "" : " nhưng chưa có kênh inject.js"}`);
        }
        pagePort?.postMessage(message.message);
        break;
      }
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
