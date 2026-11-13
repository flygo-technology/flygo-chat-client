// Runs in the page (MAIN world) before site scripts. Website signing
// plugins are reached through fetch/XHR/WebSocket calls to localhost ports;
// matching calls are handed to the extension instead of the network.
(() => {
  "use strict";
  if (window.__magicSignRelay) return;
  Object.defineProperty(window, "__magicSignRelay", { value: true });

  // Plugin ports served by the sign server; refreshed from its hello message.
  const DEFAULT_PORTS = [
    27015, 11984, 11985, 12680, 12681, 12683, 4000, 4001, 4002, 4003, 4433, 61505, 8768, 1089,
    1189, 5189, 15189, 55189, 32001, 7889, 20001, 20005, 19898, 16080,
  ];
  const LOOPBACK = new Set(["localhost", "127.0.0.1", "[::1]"]);

  const NativeWebSocket = window.WebSocket;
  const nativeFetch = window.fetch;
  const xhrProto = XMLHttpRequest.prototype;
  const nativeOpen = xhrProto.open;
  const nativeSend = xhrProto.send;
  const nativeSetRequestHeader = xhrProto.setRequestHeader;
  const nativeAbort = xhrProto.abort;

  let config = { enabled: true, ports: new Set(DEFAULT_PORTS) };
  let resolveReady;
  const ready = new Promise((resolve) => (resolveReady = resolve));
  // Without the bridge (e.g. sandboxed frames) fall back to native calls.
  setTimeout(() => resolveReady(), 1500);

  let bridge = null;
  let nextId = 1;
  const pending = new Map(); // id -> { resolve, reject } for HTTP
  const sockets = new Map(); // id -> RelayWebSocket

  function connectBridge() {
    const channel = new MessageChannel();
    bridge = channel.port1;
    bridge.onmessage = (event) => onBridgeMessage(event.data);
    window.postMessage({ __magicSign: "init" }, "*", [channel.port2]);
  }
  window.addEventListener("message", (event) => {
    if (event.source === window && event.data?.__magicSign === "bridge-ready") connectBridge();
  });
  connectBridge();

  function onBridgeMessage(message) {
    switch (message.t) {
      case "config":
        config = {
          enabled: message.enabled !== false,
          ports: new Set(message.ports?.length ? message.ports : DEFAULT_PORTS),
          debug: message.debug === true,
        };
        resolveReady();
        break;
      case "http_res": {
        const waiter = pending.get(message.id);
        pending.delete(message.id);
        if (waiter) message.error ? waiter.reject(new Error(message.error)) : waiter.resolve(message);
        break;
      }
      case "ws_opened":
        sockets.get(message.id)?._opened(message.protocol || "");
        break;
      case "ws_msg":
        sockets.get(message.id)?._message(message);
        break;
      case "ws_closed":
        sockets.get(message.id)?._closed(message.code ?? 1006, message.reason ?? "");
        sockets.delete(message.id);
        break;
    }
  }

  function parse(url) {
    try {
      return new URL(url, location.href);
    } catch {
      return null;
    }
  }

  function isCandidate(url) {
    return !!url && LOOPBACK.has(url.hostname) && /^(https?|wss?):$/.test(url.protocol);
  }

  let pluginUsed = false;

  function shouldRelay(url) {
    if (!isCandidate(url) || !bridge) return false;
    const port = Number(url.port) || (url.protocol === "https:" || url.protocol === "wss:" ? 443 : 80);
    if (!config.ports.has(port)) return false;
    // Tell the bridge this page talks to a sign plugin, so flipping the
    // on/off switch reloads it and the open plugin connections follow.
    if (!pluginUsed) {
      pluginUsed = true;
      bridge.postMessage({ t: "plugin_used" });
    }
    return config.enabled;
  }

  function toBase64(bytes) {
    let binary = "";
    for (let index = 0; index < bytes.length; index += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(index, index + 0x8000));
    }
    return btoa(binary);
  }

  function fromBase64(value) {
    const binary = atob(value || "");
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return bytes;
  }

  async function bodyBytes(body) {
    if (body == null) return null;
    if (typeof body === "string") return new TextEncoder().encode(body);
    if (body instanceof ArrayBuffer) return new Uint8Array(body);
    if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    return new Uint8Array(await new Response(body).arrayBuffer());
  }

  function relayHttp(method, url, headers, bytes) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      bridge.postMessage({
        t: "http",
        id,
        method,
        url: url.href,
        headers,
        body: bytes ? toBase64(bytes) : null,
      });
    });
  }

  // ---- debug log -------------------------------------------------------------
  // Only while an admin enabled debugging for this device and website: every
  // HTTP call and WebSocket frame of the page goes to the sign server.

  const LOG_LIMIT = 256 * 1024;
  const LOG = Symbol("magicSignLog");
  let socketSequence = 0;

  function debugLog(entry) {
    if (!config.debug || !bridge) return;
    try {
      bridge.postMessage({ t: "log", entry: { at: new Date().toISOString(), ...entry } });
    } catch {
      /* bridge gone */
    }
  }

  const clipText = (text) =>
    typeof text === "string" && text.length > LOG_LIMIT ? `${text.slice(0, LOG_LIMIT)}…[+${text.length - LOG_LIMIT}]` : text;

  function clipBase64(bytes) {
    const view = bytes.length > LOG_LIMIT ? bytes.subarray(0, LOG_LIMIT) : bytes;
    return { base64: toBase64(view), size: bytes.length };
  }

  /** Loggable form of a request or WebSocket payload. */
  async function describeBody(body) {
    if (body == null) return undefined;
    if (typeof body === "string") return clipText(body);
    if (body instanceof URLSearchParams) return clipText(body.toString());
    if (body instanceof FormData) {
      return {
        formData: [...body.entries()].map(([name, value]) =>
          typeof value === "string" ? [name, clipText(value)] : [name, `<file ${value.name} ${value.type} ${value.size}B>`],
        ),
      };
    }
    if (body instanceof ReadableStream) return "<stream>";
    if (body instanceof Blob) return clipBase64(new Uint8Array(await body.arrayBuffer()));
    if (body instanceof ArrayBuffer) return clipBase64(new Uint8Array(body));
    if (ArrayBuffer.isView(body)) return clipBase64(new Uint8Array(body.buffer, body.byteOffset, body.byteLength));
    return String(body);
  }

  const headersObject = (headers) => {
    const result = {};
    try {
      new Headers(headers || {}).forEach((value, name) => (result[name] = value));
    } catch {
      /* unusual header init */
    }
    return result;
  };

  async function responseBody(response) {
    const type = response.headers.get("content-type") || "";
    if (type && !/json|text|xml|javascript|html|x-www-form-urlencoded/i.test(type)) {
      return clipBase64(new Uint8Array(await response.arrayBuffer()));
    }
    return clipText(await response.text());
  }

  /** Read what is needed from a fetch call before the body is consumed. */
  function snapshotFetch(input, init) {
    const isRequest = input instanceof Request;
    const method = String(init?.method || (isRequest ? input.method : "GET")).toUpperCase();
    const url = parse(isRequest ? input.url : String(input))?.href || String(input);
    let body;
    if (init && "body" in init) body = describeBody(init.body);
    else if (isRequest && !["GET", "HEAD"].includes(method)) body = input.clone().text().then(clipText);
    return {
      method,
      url,
      requestHeaders: headersObject(init?.headers || (isRequest ? input.headers : undefined)),
      body: Promise.resolve(body).catch((error) => `<unreadable: ${error}>`),
      started: performance.now(),
    };
  }

  function logFetch(snapshot, result) {
    result.then(
      async (response) => {
        const url = parse(snapshot.url);
        debugLog({
          kind: "http",
          api: "fetch",
          relay: !!url && shouldRelay(url),
          method: snapshot.method,
          url: snapshot.url,
          requestHeaders: snapshot.requestHeaders,
          requestBody: await snapshot.body,
          status: response.status,
          responseHeaders: headersObject(response.headers),
          responseBody: await responseBody(response.clone()).catch((error) => `<unreadable: ${error}>`),
          ms: Math.round(performance.now() - snapshot.started),
        });
      },
      async (error) =>
        debugLog({
          kind: "http",
          api: "fetch",
          method: snapshot.method,
          url: snapshot.url,
          requestHeaders: snapshot.requestHeaders,
          requestBody: await snapshot.body,
          error: String(error),
          ms: Math.round(performance.now() - snapshot.started),
        }),
    );
  }

  function logXhr(xhr, body) {
    const state = xhr[LOG];
    if (!config.debug || !state) return;
    const started = performance.now();
    const requestBody = describeBody(body).catch((error) => `<unreadable: ${error}>`);
    xhr.addEventListener(
      "loadend",
      async () => {
        let responseBodyValue;
        try {
          if (xhr.responseType === "" || xhr.responseType === "text") responseBodyValue = clipText(xhr.responseText);
          else if (xhr.responseType === "json") responseBodyValue = clipText(JSON.stringify(xhr.response));
          else responseBodyValue = await describeBody(xhr.response);
        } catch (error) {
          responseBodyValue = `<unreadable: ${error}>`;
        }
        debugLog({
          kind: "http",
          api: "xhr",
          relay: !!xhr[RELAY],
          method: state.method,
          url: state.url,
          requestHeaders: state.headers,
          requestBody: await requestBody,
          status: xhr.status,
          responseHeaders: xhr.getAllResponseHeaders(),
          responseBody: responseBodyValue,
          ms: Math.round(performance.now() - started),
        });
      },
      { once: true },
    );
  }

  function logSocket(id, url, relay, event, extra = {}) {
    debugLog({ kind: "ws", socket: id, url, relay, event, ...extra });
  }

  async function socketData(data) {
    return typeof data === "string" ? clipText(data) : describeBody(data);
  }

  /** Follow a WebSocket that is not handled by the extension. */
  function watchNativeSocket(socket, url) {
    const id = ++socketSequence;
    logSocket(id, url, false, "connect");
    socket.addEventListener("open", () => logSocket(id, url, false, "open", { protocol: socket.protocol }));
    socket.addEventListener("message", async (event) => logSocket(id, url, false, "recv", { data: await socketData(event.data) }));
    socket.addEventListener("error", () => logSocket(id, url, false, "error"));
    socket.addEventListener("close", (event) => logSocket(id, url, false, "close", { code: event.code, reason: event.reason }));
    const send = socket.send;
    socket.send = function (data) {
      if (config.debug) socketData(data).then((payload) => logSocket(id, url, false, "send", { data: payload }));
      return send.call(this, data);
    };
  }

  // ---- fetch ---------------------------------------------------------------

  function pluginFetch(input, init) {
    const url = parse(input instanceof Request ? input.url : String(input));
    if (!isCandidate(url)) return nativeFetch.apply(this, arguments);
    return ready.then(async () => {
      if (!shouldRelay(url)) return nativeFetch.call(window, input, init);
      const request = new Request(input, init);
      const headers = {};
      request.headers.forEach((value, name) => (headers[name] = value));
      const bytes =
        request.method === "GET" || request.method === "HEAD"
          ? null
          : new Uint8Array(await request.arrayBuffer());
      let response;
      try {
        response = await relayHttp(request.method, url, headers, bytes);
      } catch {
        throw new TypeError("Failed to fetch");
      }
      const nullBody = [101, 204, 205, 304].includes(response.status);
      return new Response(nullBody ? null : fromBase64(response.body), {
        status: response.status,
        headers: response.headers,
      });
    });
  }

  window.fetch = function fetch(input, init) {
    const snapshot = config.debug ? snapshotFetch(input, init) : null;
    const result = pluginFetch.call(this, input, init);
    if (snapshot) logFetch(snapshot, result);
    return result;
  };

  // ---- XMLHttpRequest ------------------------------------------------------

  const RELAY = Symbol("magicSignRelay");

  function define(xhr, values) {
    for (const [key, value] of Object.entries(values)) {
      Object.defineProperty(xhr, key, { value, configurable: true, writable: true });
    }
  }

  function fire(xhr, type) {
    xhr.dispatchEvent(new Event(type));
  }

  xhrProto.open = function open(method, url, async) {
    const parsed = parse(String(url));
    this[LOG] = { method: String(method).toUpperCase(), url: parsed?.href || String(url), headers: {} };
    if (isCandidate(parsed) && async !== false) {
      this[RELAY] = { method: String(method).toUpperCase(), url: parsed, headers: {}, aborted: false };
      define(this, { readyState: 1, status: 0, statusText: "", responseText: "", response: "", responseURL: "" });
      fire(this, "readystatechange");
      return;
    }
    delete this[RELAY];
    return nativeOpen.apply(this, arguments);
  };

  xhrProto.setRequestHeader = function setRequestHeader(name, value) {
    if (this[LOG]) this[LOG].headers[name] = String(value);
    if (this[RELAY]) {
      this[RELAY].headers[name.toLowerCase()] = String(value);
      return;
    }
    return nativeSetRequestHeader.apply(this, arguments);
  };

  xhrProto.abort = function abort() {
    if (this[RELAY]) {
      this[RELAY].aborted = true;
      define(this, { readyState: 0 });
      fire(this, "abort");
      fire(this, "loadend");
      return;
    }
    return nativeAbort.apply(this, arguments);
  };

  xhrProto.send = function send(body) {
    logXhr(this, body);
    const state = this[RELAY];
    if (!state) return nativeSend.apply(this, arguments);
    const xhr = this;
    fire(xhr, "loadstart");
    ready
      .then(async () => {
        if (!shouldRelay(state.url)) {
          // Not served by the sign server: replay the call natively.
          delete xhr[RELAY];
          for (const key of ["readyState", "status", "statusText", "responseText", "response", "responseURL"]) delete xhr[key];
          nativeOpen.call(xhr, state.method, state.url.href, true);
          for (const [name, value] of Object.entries(state.headers)) nativeSetRequestHeader.call(xhr, name, value);
          nativeSend.call(xhr, body);
          return;
        }
        const bytes = state.method === "GET" || state.method === "HEAD" ? null : await bodyBytes(body);
        const response = await relayHttp(state.method, state.url, state.headers, bytes);
        if (state.aborted) return;
        const raw = fromBase64(response.body);
        const text = new TextDecoder().decode(raw);
        const headers = Object.entries(response.headers || {});
        let value = text;
        switch (xhr.responseType) {
          case "json":
            try {
              value = JSON.parse(text);
            } catch {
              value = null;
            }
            break;
          case "arraybuffer":
            value = raw.buffer;
            break;
          case "blob":
            value = new Blob([raw], { type: response.headers?.["content-type"] || "" });
            break;
        }
        define(xhr, {
          status: response.status,
          statusText: "",
          responseURL: state.url.href,
          getAllResponseHeaders: () => headers.map(([name, item]) => `${name}: ${item}\r\n`).join(""),
          getResponseHeader: (name) => {
            const found = headers.find(([key]) => key.toLowerCase() === String(name).toLowerCase());
            return found ? found[1] : null;
          },
        });
        define(xhr, { readyState: 2 });
        fire(xhr, "readystatechange");
        define(xhr, { readyState: 3 });
        fire(xhr, "readystatechange");
        define(xhr, {
          readyState: 4,
          responseText: xhr.responseType === "" || xhr.responseType === "text" ? text : "",
          response: value,
        });
        fire(xhr, "readystatechange");
        fire(xhr, "load");
        fire(xhr, "loadend");
      })
      .catch(() => {
        if (state.aborted) return;
        define(xhr, { readyState: 4, status: 0 });
        fire(xhr, "readystatechange");
        fire(xhr, "error");
        fire(xhr, "loadend");
      });
  };

  // ---- WebSocket -----------------------------------------------------------

  class RelayWebSocket extends EventTarget {
    constructor(url, protocols) {
      super();
      this._url = url.href;
      this._readyState = 0;
      this._protocol = "";
      this._binaryType = "blob";
      this._native = null;
      this._id = 0;
      this._handlers = { open: null, message: null, error: null, close: null };
      this._logId = ++socketSequence;
      this._relay = false;
      const list = protocols == null ? [] : Array.isArray(protocols) ? protocols : [protocols];
      ready.then(() => {
        if (this._readyState !== 0) return;
        this._relay = shouldRelay(url);
        this._log("connect", { protocols: list.map(String) });
        if (this._relay) {
          this._id = nextId++;
          sockets.set(this._id, this);
          bridge.postMessage({ t: "ws_open", id: this._id, url: this._url, protocols: list.map(String) });
        } else {
          this._attachNative(new NativeWebSocket(this._url, list));
        }
      });
    }

    _log(event, extra) {
      if (config.debug) logSocket(this._logId, this._url, this._relay, event, extra);
    }

    _attachNative(socket) {
      this._native = socket;
      socket.binaryType = this._binaryType;
      socket.onopen = () => this._opened(socket.protocol);
      socket.onmessage = (event) => {
        if (config.debug) socketData(event.data).then((data) => this._log("recv", { data }));
        this._emit(new MessageEvent("message", { data: event.data, origin: event.origin }));
      };
      socket.onerror = () => this._emit(new Event("error"));
      socket.onclose = (event) => this._closed(event.code, event.reason, event.wasClean);
    }

    _emit(event) {
      const handler = this._handlers[event.type];
      this.dispatchEvent(event);
      if (typeof handler === "function") handler.call(this, event);
    }

    _opened(protocol) {
      if (this._readyState !== 0) return;
      this._readyState = 1;
      this._protocol = protocol;
      this._log("open", { protocol });
      this._emit(new Event("open"));
    }

    _message(message) {
      if (this._readyState !== 1) return;
      this._log("recv", { data: message.text !== undefined ? clipText(message.text) : { base64: message.binary } });
      let data = message.text;
      if (data === undefined) {
        const bytes = fromBase64(message.binary);
        data = this._binaryType === "arraybuffer" ? bytes.buffer : new Blob([bytes]);
      }
      this._emit(new MessageEvent("message", { data, origin: new URL(this._url).origin }));
    }

    _closed(code, reason, wasClean = code === 1000) {
      if (this._readyState === 3) return;
      const failedToOpen = this._readyState === 0;
      this._readyState = 3;
      this._log("close", { code, reason, wasClean });
      if (failedToOpen || !wasClean) this._emit(new Event("error"));
      this._emit(new CloseEvent("close", { code, reason, wasClean }));
    }

    get url() {
      return this._url;
    }
    get readyState() {
      return this._readyState;
    }
    get protocol() {
      return this._protocol;
    }
    get extensions() {
      return "";
    }
    get bufferedAmount() {
      return this._native ? this._native.bufferedAmount : 0;
    }
    get binaryType() {
      return this._binaryType;
    }
    set binaryType(value) {
      this._binaryType = value;
      if (this._native) this._native.binaryType = value;
    }

    send(data) {
      if (this._readyState === 0) throw new DOMException("Still in CONNECTING state.", "InvalidStateError");
      if (this._readyState !== 1) return;
      if (config.debug) socketData(data).then((payload) => this._log("send", { data: payload }));
      if (this._native) return this._native.send(data);
      if (typeof data === "string") {
        bridge.postMessage({ t: "ws_send", id: this._id, text: data });
      } else {
        bodyBytes(data).then((bytes) => bridge.postMessage({ t: "ws_send", id: this._id, binary: toBase64(bytes) }));
      }
    }

    close(code, reason) {
      if (this._readyState >= 2) return;
      if (this._native) return this._native.close(code, reason);
      const wasConnecting = this._readyState === 0;
      this._readyState = 2;
      if (this._id) bridge.postMessage({ t: "ws_close", id: this._id, code, reason });
      if (wasConnecting && !this._id) this._closed(code ?? 1000, reason ?? "", true);
    }
  }

  // The native prototype's `on*` accessors only accept real sockets, so the
  // relay socket keeps its own.
  for (const type of ["open", "message", "error", "close"]) {
    Object.defineProperty(RelayWebSocket.prototype, "on" + type, {
      get() {
        return this._handlers[type];
      },
      set(handler) {
        this._handlers[type] = typeof handler === "function" ? handler : null;
      },
      configurable: true,
    });
  }

  // Keep `socket instanceof WebSocket` and the static constants working.
  Object.setPrototypeOf(RelayWebSocket.prototype, NativeWebSocket.prototype);
  for (const [name, value] of Object.entries({ CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })) {
    Object.defineProperty(RelayWebSocket.prototype, name, { value });
  }

  function WebSocket(url, protocols) {
    if (!new.target) throw new TypeError("Failed to construct 'WebSocket': Please use the 'new' operator");
    const parsed = parse(String(url));
    if (!isCandidate(parsed)) {
      const socket = protocols === undefined ? new NativeWebSocket(url) : new NativeWebSocket(url, protocols);
      if (config.debug) watchNativeSocket(socket, parsed?.href || String(url));
      return socket;
    }
    return new RelayWebSocket(parsed, protocols);
  }
  WebSocket.prototype = NativeWebSocket.prototype;
  for (const name of ["CONNECTING", "OPEN", "CLOSING", "CLOSED"]) WebSocket[name] = NativeWebSocket[name];
  window.WebSocket = WebSocket;
})();
