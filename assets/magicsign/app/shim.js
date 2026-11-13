// The `chrome.*` APIs the extension uses, for the app's own pages: the hidden
// engine page (background.js), the popup/options/help pages and the overlay
// that shows the signing dialog (prompt.js). Every call goes to the Flutter
// host (lib/host.dart) through the `ms` handler; the host calls back through
// `window.__ms`. Websites never get this file: they get page-bridge.js.
(() => {
  "use strict";
  if (window.__ms) return;

  const call = (op, args = {}) => window.flutter_inappwebview.callHandler("ms", { op, ...args });
  const role = window.__msRole || "page"; // engine | page | prompt
  const base = new URL(".", document.currentScript?.src || location.href).href.replace(/app\/$/, "ext/");

  function event() {
    const listeners = new Set();
    return {
      addListener: (fn) => listeners.add(fn),
      removeListener: (fn) => listeners.delete(fn),
      hasListener: (fn) => listeners.has(fn),
      emit: (...args) => [...listeners].map((fn) => fn(...args)),
    };
  }

  const storageChanged = event();
  const runtimeMessage = event();
  const runtimeConnect = event();
  const tabsUpdated = event();
  const tabsRemoved = event();
  const alarmFired = event();
  const noopEvent = event();

  // ---- runtime.onMessage: reply like Chrome (sync reply or `return true`) ----
  function deliverMessage(message, sender) {
    return new Promise((resolve) => {
      let answered = false;
      const reply = (value) => {
        if (answered) return;
        answered = true;
        resolve(value === undefined ? null : value);
      };
      const results = runtimeMessage.emit(message, sender, reply);
      if (!answered && !results.some((result) => result === true)) {
        answered = true;
        resolve(null);
      }
    });
  }

  // ---- ports (engine side) ---------------------------------------------------
  const ports = new Map();
  function makePort(id, name, sender) {
    const onMessage = event();
    const onDisconnect = event();
    const port = {
      name,
      sender,
      onMessage,
      onDisconnect,
      postMessage: (message) => void call("port.post", { port: id, message }),
      disconnect: () => {
        ports.delete(id);
        void call("port.disconnect", { port: id });
      },
    };
    ports.set(id, port);
    return port;
  }

  window.__ms = {
    storageChanged: (changes) => storageChanged.emit(changes, "local"),
    message: (message, sender) => deliverMessage(message, sender),
    connect: (id, name, sender) => runtimeConnect.emit(makePort(id, name, sender)),
    portMessage: (id, message) => ports.get(id)?.onMessage.emit(message),
    portClosed: (id) => {
      const port = ports.get(id);
      ports.delete(id);
      port?.onDisconnect.emit(port);
    },
    tabUpdated: (tab) => tabsUpdated.emit(tab.id, { url: tab.url }, tab),
    tabRemoved: (id) => tabsRemoved.emit(id, {}),
  };

  let manifest = null;
  const manifestReady = fetch(`${base}manifest.json`)
    .then((reply) => reply.json())
    .then((value) => (manifest = value))
    .catch(() => (manifest = { version: "0" }));

  // ---- alarms: timers while the app runs -------------------------------------
  const alarms = new Map();
  function createAlarm(name, info = {}) {
    clearInterval(alarms.get(name));
    clearTimeout(alarms.get(name));
    const first = (info.delayInMinutes ?? info.periodInMinutes ?? 0) * 60_000;
    const fire = () => alarmFired.emit({ name });
    const timer = setTimeout(() => {
      fire();
      if (info.periodInMinutes) alarms.set(name, setInterval(fire, info.periodInMinutes * 60_000));
    }, first);
    alarms.set(name, timer);
  }

  window.chrome = {
    runtime: {
      id: "vn.flygo.magic-sign",
      getURL: (path = "") => `${base}${path}`,
      getManifest: () => manifest || { version: "0" },
      sendMessage: (message) => call("runtime.sendMessage", { message }),
      openOptionsPage: () => call("open", { page: "options.html" }),
      onMessage: runtimeMessage,
      onConnect: runtimeConnect,
      onStartup: noopEvent,
      onInstalled: noopEvent,
    },
    storage: {
      local: {
        get: (keys) => call("storage.get", { keys: keys == null ? null : [].concat(keys) }),
        set: (items) => call("storage.set", { items }),
        remove: (keys) => call("storage.remove", { keys: [].concat(keys) }),
      },
      managed: { get: () => call("storage.managed") },
      onChanged: storageChanged,
    },
    tabs: {
      query: (query) => call("tabs.query", { query }),
      create: ({ url }) => call("tabs.create", { url }),
      sendMessage: async (tabId, message) => {
        const ok = await call("tabs.sendMessage", { tabId, message });
        if (!ok) throw new Error("Could not establish connection. Receiving end does not exist.");
      },
      onUpdated: tabsUpdated,
      onRemoved: tabsRemoved,
    },
    identity: {
      getRedirectURL: (path = "") => `vn.flygo.magic-sign://${path}`,
      launchWebAuthFlow: async ({ url }) => {
        const result = await call("identity.auth", { url });
        if (!result?.url) throw new Error(result?.error || "Đã huỷ đăng nhập");
        return result.url;
      },
    },
    alarms: { create: createAlarm, onAlarm: alarmFired },
    action: { setBadgeText: () => {}, setBadgeBackgroundColor: () => {} },
    // Debug capture of whole requests needs Chrome's webRequest; the app only
    // has what inject.js logs inside the page.
    webRequest: { onBeforeRequest: noopEvent, onSendHeaders: noopEvent, onHeadersReceived: noopEvent, onCompleted: noopEvent, onErrorOccurred: noopEvent },
  };

  if (role === "engine") {
    // background.js loads its helpers with importScripts(); engine.html loads
    // them with <script> tags first.
    window.importScripts = () => {};
    // The extension may fetch any host (host_permissions); a page may not, so
    // requests to other origins go through the app (no CORS).
    const pageFetch = window.fetch.bind(window);
    window.fetch = async (input, init = {}) => {
      const url = new URL(typeof input === "string" ? input : input.url, location.href);
      if (url.origin === location.origin) return pageFetch(input, init);
      const signal = init.signal;
      if (signal?.aborted) throw new DOMException("Aborted", "AbortError");
      let body = init.body ?? null;
      if (body instanceof URLSearchParams) body = body.toString();
      const request = call("fetch", {
        url: url.href,
        method: init.method || "GET",
        headers: Object.fromEntries(new Headers(init.headers || {}).entries()),
        body: typeof body === "string" ? body : null,
      });
      const aborted = new Promise((_, reject) =>
        signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true }),
      );
      const reply = await Promise.race([request, aborted]);
      if (reply.error) throw new TypeError(reply.error);
      const bytes = Uint8Array.from(atob(reply.body || ""), (c) => c.charCodeAt(0));
      return new Response(reply.status === 204 || reply.status === 304 ? null : bytes, {
        status: reply.status,
        headers: reply.headers,
      });
    };
  }

  // The desktop app shows these pages at their Chrome size.
  if (role === "page" && !window.__msDesktop) {
    // The extension pages have no viewport tag (Chrome draws them at 320px):
    // lay them out at the phone's width, with text and buttons sized for touch.
    const viewport = document.createElement("meta");
    viewport.name = "viewport";
    viewport.content = "width=device-width, initial-scale=1, viewport-fit=cover";
    const style = document.createElement("style");
    style.textContent = `
      :root { font-size: 15px !important; -webkit-text-size-adjust: 100%; }
      body { width: auto !important; max-width: 640px; margin: 0 auto !important; padding: 4px 16px 24px !important; gap: 12px !important; }
      .brand strong { font-size: 17px !important; }
      .faint, .label, .pill, .hint { font-size: 12px !important; }
      .title { font-size: 18px !important; }
      .card { padding: 14px 16px !important; border-radius: 14px !important; }
      .btn { min-height: 44px; padding: 10px 18px !important; border-radius: 10px !important; }
      .link { padding: 10px 0 !important; }
      .icon-btn { min-width: 40px; min-height: 40px; }
      .links { flex-wrap: wrap; gap: 4px 12px; }
      .token-line { font-size: 14px; }
      .id { font-size: 15px !important; }
      input, select, textarea { font-size: 16px !important; }
      /* The app is always on. */
      .power { display: none !important; }
      .alert { padding: 14px 16px !important; }
    `;
    const head = document.head || document.documentElement;
    head.prepend(viewport);
    document.documentElement.append(style);
    // Later in the cascade than the page's own stylesheet.
    document.addEventListener("DOMContentLoaded", () => document.head.append(style));
  }

  if (role === "prompt") {
    // prompt.js asks for the phone's biometrics before a signature.
    window.__msConfirm = (options = {}) => call("biometric", { remember: !!options.remember });
    window.__msRemembered = () => call("biometricRemembered");
    // The overlay is only shown while prompt.js has its dialog on screen.
    let shown = false;
    const watch = () => {
      const visible = (document.body?.children.length || 0) > 0;
      if (visible === shown) return;
      shown = visible;
      void call("overlay", { visible });
    };
    new MutationObserver(watch).observe(document, { childList: true, subtree: true });
  }

  window.__msReady = manifestReady;
})();
