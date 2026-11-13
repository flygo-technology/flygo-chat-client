// Relay mode: reach an agent through wss://remote-sign-relay.flygo.vn instead of logging
// in to a sign server. `RelaySocket` behaves like the WebSocket the service
// worker used to open to the server (readyState, send, close, onmessage,
// onclose), but every message is end-to-end encrypted to one agent
// (e2e.js, docs/relay-protocol.md). Loaded with importScripts() after e2e.js.
(() => {
  "use strict";
  const E2E = globalThis.MagicSignE2E;
  const DEFAULT_RELAY = "wss://remote-sign-relay.flygo.vn/v1";
  const HANDSHAKE_TIMEOUT = 20_000;
  const AGENT_PING = 30_000;
  // Same limits as the agent (docs/relay-protocol.md, "Tin nhắn lớn").
  const CHUNK_BYTES = 192 * 1024;
  const MAX_MESSAGE_BYTES = 64 * 1024 * 1024;
  // The relay drops frames above 50 per second per connection.
  const FRAMES_PER_SECOND = 40;

  // ---- identity (IndexedDB keeps the non-extractable private key) ----------

  function database() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open("magic-sign", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("keys");
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function stored(key, value) {
    const db = await database();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction("keys", value === undefined ? "readonly" : "readwrite");
      const store = transaction.objectStore("keys");
      const request = value === undefined ? store.get(key) : store.put(value, key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  let identityPromise = null;
  /** This browser's key pair, created on first use. */
  function identity() {
    identityPromise ||= (async () => {
      const keys = await stored("identity");
      if (keys) return E2E.identityFromKeys(keys);
      const created = await E2E.generateIdentity();
      await stored("identity", { privateKey: created.privateKey, publicKey: created.publicKey });
      return created;
    })();
    // A failure (e.g. storage busy at startup) is retried on the next call.
    identityPromise.catch(() => {
      identityPromise = null;
    });
    return identityPromise;
  }

  // ---- one connection to the relay, shared by every agent -------------------

  const hub = {
    ws: null,
    ready: false,
    url: DEFAULT_RELAY,
    sockets: new Map(), // agent ID -> RelaySocket
    waiting: [],

    async open(url) {
      this.url = url || DEFAULT_RELAY;
      if (this.ws && this.ws.readyState <= 1) return this.whenReady();
      const me = await identity();
      const ws = new WebSocket(`${this.url}/connect?id=${me.id}`);
      this.ws = ws;
      this.ready = false;
      ws.onmessage = async (event) => {
        const frame = JSON.parse(event.data);
        if (frame.t === "challenge") {
          ws.send(JSON.stringify({ t: "auth", ...(await E2E.relayAuth(me, E2E.fromBase64(frame.nonce))) }));
        } else if (frame.t === "ready") {
          this.ready = true;
          this.waiting.splice(0).forEach((resolve) => resolve(true));
        } else if (frame.t === "recv") {
          this.sockets.get(frame.from)?.receive(frame.data);
        } else if (frame.t === "error" && frame.to) {
          this.sockets.get(frame.to)?.fail(frame.code === "offline" ? "Agent đang tắt hoặc mất mạng" : `Relay báo lỗi ${frame.code}`);
        }
      };
      ws.onclose = () => {
        if (this.ws !== ws) return;
        this.ws = null;
        this.ready = false;
        this.waiting.splice(0).forEach((resolve) => resolve(false));
        for (const socket of [...this.sockets.values()]) socket.fail("Mất kết nối relay");
      };
      return this.whenReady();
    },

    whenReady() {
      if (this.ready) return Promise.resolve(true);
      return new Promise((resolve) => {
        this.waiting.push(resolve);
        setTimeout(() => resolve(false), HANDSHAKE_TIMEOUT);
      });
    },

    queue: [],
    window: { start: 0, count: 0 },
    timer: null,

    send(to, data) {
      if (!this.ready) return;
      this.queue.push(JSON.stringify({ t: "send", to, data: JSON.stringify(data) }));
      this.flush();
    },

    flush() {
      if (this.timer) return;
      while (this.queue.length && this.ready) {
        const now = Date.now();
        if (now - this.window.start >= 1000) this.window = { start: now, count: 0 };
        if (this.window.count >= FRAMES_PER_SECOND) {
          this.timer = setTimeout(() => {
            this.timer = null;
            this.flush();
          }, this.window.start + 1000 - now);
          return;
        }
        this.window.count++;
        this.ws.send(this.queue.shift());
      }
      if (!this.ready) this.queue.length = 0;
    },
  };

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  /** `text` as sealed messages: itself, or ordered `chunk` messages. */
  function splitMessage(text, id) {
    const bytes = encoder.encode(text);
    if (bytes.length <= CHUNK_BYTES) return [text];
    const total = Math.ceil(bytes.length / CHUNK_BYTES);
    const parts = [];
    for (let index = 0; index < total; index++) {
      const piece = bytes.subarray(index * CHUNK_BYTES, (index + 1) * CHUNK_BYTES);
      parts.push(`{"t":"chunk","id":${id},"i":${index},"n":${total},"d":"${E2E.toBase64(piece)}"}`);
    }
    return parts;
  }

  /**
   * A WebSocket-like link to one agent. `onAccess(state, detail)` reports
   * `welcome`, `pending`, `invalid_invite`, `revoked` or `catalog`.
   */
  class RelaySocket {
    constructor(agentId, { relayUrl, invite, deviceName, onAccess }) {
      Object.assign(this, { agentId, invite, deviceName, onAccess, readyState: 0, session: null, pending: null });
      this.onmessage = null;
      this.onclose = null;
      hub.sockets.get(agentId)?.close(1000, "replaced");
      hub.sockets.set(agentId, this);
      this.timer = setTimeout(() => this.fail("Agent không trả lời"), HANDSHAKE_TIMEOUT);
      void this.start(relayUrl);
    }

    async start(relayUrl) {
      if (!(await hub.open(relayUrl))) return this.fail("Không kết nối được relay");
      const { hello, pending } = await E2E.startHello(await identity(), this.agentId, Date.now());
      this.pending = pending;
      hub.send(this.agentId, { t: "hello", ...hello });
    }

    async receive(raw) {
      if (this.readyState === 3) return;
      let data;
      try {
        data = JSON.parse(raw);
      } catch {
        return;
      }
      try {
        if (data.t === "hello_ok" && this.pending) {
          this.session = await E2E.finishHello(this.pending, data);
          this.pending = null;
          await this.sendPlain({ t: "join", deviceName: this.deviceName, invite: this.invite || null });
          return;
        }
        if (data.t === "hello_err") return this.fail(`Agent từ chối kết nối (${data.code})`);
        if (data.t !== "data" || !this.session) return;
        const text = this.assemble(decoder.decode(await this.session.open(data)));
        if (text === null) return;
        const message = JSON.parse(text);
        this.control(message) || this.onmessage?.({ data: JSON.stringify(message) });
      } catch (error) {
        this.fail(error.message || "Lỗi giải mã");
      }
    }

    /**
     * A whole message, or null while a chunked one is incomplete. Decryption
     * is async, so pieces are placed by index rather than arrival.
     */
    assemble(text) {
      if (!text.startsWith('{"t":"chunk"')) return text;
      const chunk = JSON.parse(text);
      let entry = (this.chunks ||= new Map()).get(chunk.id);
      if (!entry) {
        entry = { parts: new Array(chunk.n), got: 0, size: 0 };
        this.chunks.set(chunk.id, entry);
      }
      if (entry.parts[chunk.i]) return null;
      const piece = E2E.fromBase64(chunk.d);
      entry.size += piece.length;
      if (entry.size > MAX_MESSAGE_BYTES) {
        this.chunks.delete(chunk.id);
        throw new Error("Tin nhắn quá lớn");
      }
      entry.parts[chunk.i] = piece;
      if (++entry.got < chunk.n) return null;
      this.chunks.delete(chunk.id);
      const whole = new Uint8Array(entry.size);
      let offset = 0;
      for (const part of entry.parts) {
        whole.set(part, offset);
        offset += part.length;
      }
      return decoder.decode(whole);
    }

    /** Session control messages; returns true when handled here. */
    control(message) {
      switch (message.t) {
        case "welcome":
          clearTimeout(this.timer);
          this.invite = null;
          this.readyState = 1;
          this.ping = setInterval(() => this.send(JSON.stringify({ t: "ping" })), AGENT_PING);
          this.onAccess?.("welcome", message);
          return true;
        case "catalog":
          this.onAccess?.("catalog", message);
          return true;
        case "denied":
          clearTimeout(this.timer);
          this.onAccess?.(message.reason, message);
          if (message.reason !== "pending") this.close(4003, message.reason);
          return true;
        case "revoke":
          this.onAccess?.("revoked", message);
          this.close(4003, "revoked");
          return true;
        default:
          return false;
      }
    }

    sendPlain(message) {
      this.send(JSON.stringify(message));
      return this.chain;
    }

    /** Seal and send in call order: the agent requires frames in sequence. */
    send(text) {
      if (!this.session) return;
      const parts = splitMessage(text, (this.chunkId = (this.chunkId || 0) + 1));
      for (const part of parts) {
        this.chain = (this.chain || Promise.resolve())
          .then(() => this.session.seal(part))
          .then((frame) => hub.send(this.agentId, { t: "data", ...frame }))
          .catch(() => this.fail("Không mã hoá được dữ liệu"));
      }
    }

    fail(reason) {
      this.close(1006, reason);
    }

    close(code = 1000, reason = "") {
      if (this.readyState === 3) return;
      this.readyState = 3;
      clearTimeout(this.timer);
      clearInterval(this.ping);
      if (hub.sockets.get(this.agentId) === this) hub.sockets.delete(this.agentId);
      this.onclose?.({ code, reason });
    }
  }

  globalThis.MagicSignRelay = {
    DEFAULT_RELAY,
    RelaySocket,
    splitMessage,
    identity,
    async extensionId() {
      return E2E.formatId((await identity()).id);
    },
  };
})();
