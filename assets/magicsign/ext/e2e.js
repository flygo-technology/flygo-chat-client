// End-to-end encryption between this extension and an agent through the
// relay. Mirrors src/relay_proto.rs; tests/relay-crypto-vectors.json keeps
// both sides identical (see e2e.test.mjs). Loaded with importScripts() in the
// service worker and with require() in Node tests.
(() => {
  "use strict";
  const subtle = globalThis.crypto.subtle;
  const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const HELLO_CONTEXT = "MSR1-hello";
  const HELLO_OK_CONTEXT = "MSR1-hello-ok";
  const RELAY_AUTH_CONTEXT = "MSR1-relay-auth";
  const SESSION_INFO = "MSR1 session keys";
  const EXTENSION_TO_AGENT = Uint8Array.of(0x45, 0x32, 0x41, 0); // "E2A\0"
  const AGENT_TO_EXTENSION = Uint8Array.of(0x41, 0x32, 0x45, 0); // "A2E\0"
  const ECDSA = { name: "ECDSA", namedCurve: "P-256" };
  const ECDSA_SHA256 = { name: "ECDSA", hash: "SHA-256" };
  const ECDH = { name: "ECDH", namedCurve: "P-256" };
  const text = new TextEncoder();

  // In slices: spreading a large array into one call overflows the stack.
  function toBase64(bytes) {
    const view = new Uint8Array(bytes);
    let binary = "";
    for (let offset = 0; offset < view.length; offset += 0x8000) {
      binary += String.fromCharCode(...view.subarray(offset, offset + 0x8000));
    }
    return btoa(binary);
  }
  const fromBase64 = (value) => Uint8Array.from(atob(value), (char) => char.charCodeAt(0));

  function concat(...parts) {
    const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      out.set(part, offset);
      offset += part.length;
    }
    return out;
  }

  /** Length-prefixed field of a signed transcript. */
  function field(value) {
    const bytes = typeof value === "string" ? text.encode(value) : new Uint8Array(value);
    return concat(Uint8Array.of(bytes.length >> 8, bytes.length & 255), bytes);
  }

  function base32(bytes) {
    let out = "";
    let buffer = 0;
    let bits = 0;
    for (const byte of bytes) {
      buffer = ((buffer << 8) | byte) & 0xffff;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out += ALPHABET[(buffer >> bits) & 31];
      }
    }
    if (bits > 0) out += ALPHABET[(buffer << (5 - bits)) & 31];
    return out;
  }

  const sha256 = async (bytes) => new Uint8Array(await subtle.digest("SHA-256", bytes));

  async function idFromSpki(spki) {
    return base32((await sha256(spki)).slice(0, 10));
  }

  const formatId = (id) => id.match(/.{1,4}/g).join("-");

  function normalizeId(input) {
    const id = String(input || "").replace(/[\s-]/g, "").toUpperCase();
    return id.length === 16 && [...id].every((char) => ALPHABET.includes(char)) ? id : null;
  }

  async function verify(spki, message, signature) {
    const key = await subtle.importKey("spki", spki, ECDSA, false, ["verify"]);
    return subtle.verify(ECDSA_SHA256, key, signature, message);
  }

  /** Identity from a CryptoKeyPair (private key may be non-extractable). */
  async function identityFromKeys({ privateKey, publicKey }) {
    const spki = new Uint8Array(await subtle.exportKey("spki", publicKey));
    return { privateKey, publicKey, spki, id: await idFromSpki(spki) };
  }

  async function generateIdentity() {
    return identityFromKeys(await subtle.generateKey(ECDSA, false, ["sign", "verify"]));
  }

  /** Identity from a private JWK (tests and key import). */
  async function importIdentity(jwk) {
    const privateKey = await subtle.importKey("jwk", jwk, ECDSA, false, ["sign"]);
    const { d: _d, ...publicJwk } = jwk;
    const publicKey = await subtle.importKey("jwk", publicJwk, ECDSA, true, ["verify"]);
    return identityFromKeys({ privateKey, publicKey });
  }

  const sign = async (identity, message) => new Uint8Array(await subtle.sign(ECDSA_SHA256, identity.privateKey, message));

  /** Answer to the relay's login challenge. */
  async function relayAuth(identity, nonce) {
    const message = concat(text.encode(RELAY_AUTH_CONTEXT), field(nonce));
    return { publicKey: toBase64(identity.spki), signature: toBase64(await sign(identity, message)) };
  }

  function helloTranscript(to, spki, eph, ts) {
    const time = new Uint8Array(8);
    new DataView(time.buffer).setBigInt64(0, BigInt(ts));
    return concat(text.encode(HELLO_CONTEXT), field(to), field(spki), field(eph), time);
  }

  async function helloOkTranscript(hello, spki, eph) {
    return concat(text.encode(HELLO_OK_CONTEXT), await sha256(hello), field(spki), field(eph));
  }

  /**
   * Start a session with `agentId`. `ephemeral` (an ECDH key pair) is only
   * passed by tests.
   */
  async function startHello(identity, agentId, nowMs, ephemeral) {
    const eph = ephemeral || (await subtle.generateKey(ECDH, false, ["deriveBits"]));
    const ephPublic = new Uint8Array(await subtle.exportKey("raw", eph.publicKey));
    const transcript = helloTranscript(agentId, identity.spki, ephPublic, nowMs);
    const hello = {
      v: 1,
      to: agentId,
      pub: toBase64(identity.spki),
      eph: toBase64(ephPublic),
      ts: nowMs,
      sig: toBase64(await sign(identity, transcript)),
    };
    return { hello, pending: { eph, transcript, agentId } };
  }

  async function deriveKeys(shared, hello, helloOk) {
    const salt = await sha256(concat(hello, helloOk));
    const material = await subtle.importKey("raw", shared, "HKDF", false, ["deriveBits"]);
    const okm = new Uint8Array(
      await subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info: text.encode(SESSION_INFO) }, material, 512),
    );
    const aes = (bytes) => subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
    return { toAgent: await aes(okm.slice(0, 32)), toExtension: await aes(okm.slice(32)) };
  }

  /** Check the agent's answer and open the session. */
  async function finishHello(pending, answer) {
    const spki = fromBase64(answer.pub);
    if ((await idFromSpki(spki)) !== pending.agentId) throw new Error("Khoá của agent không khớp Agent ID");
    const eph = fromBase64(answer.eph);
    const transcript = await helloOkTranscript(pending.transcript, spki, eph);
    if (!(await verify(spki, transcript, fromBase64(answer.sig)))) throw new Error("Chữ ký của agent không hợp lệ");
    const peer = await subtle.importKey("raw", eph, ECDH, false, []);
    const shared = new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: peer }, pending.eph.privateKey, 256));
    const keys = await deriveKeys(shared, pending.transcript, transcript);
    return new Session(keys.toAgent, EXTENSION_TO_AGENT, keys.toExtension, AGENT_TO_EXTENSION, pending.agentId);
  }

  function nonce(tag, counter) {
    const iv = new Uint8Array(12);
    iv.set(tag);
    new DataView(iv.buffer).setBigUint64(4, BigInt(counter));
    return iv;
  }

  /** Encrypts and decrypts frames in order, one key per direction. */
  class Session {
    constructor(sendKey, sendTag, receiveKey, receiveTag, peerId) {
      Object.assign(this, { sendKey, sendTag, receiveKey, receiveTag, peerId, sendNext: 0, receiveNext: 0 });
    }

    async seal(plaintext) {
      const n = this.sendNext++;
      const bytes = typeof plaintext === "string" ? text.encode(plaintext) : plaintext;
      const ciphertext = await subtle.encrypt({ name: "AES-GCM", iv: nonce(this.sendTag, n) }, this.sendKey, bytes);
      return { n, c: toBase64(ciphertext) };
    }

    // The counter moves before decrypting, so frames handled by concurrent
    // event handlers are still checked in arrival order.
    async open(frame) {
      if (frame.n !== this.receiveNext) throw new Error(`Gói tin sai thứ tự (mong ${this.receiveNext}, nhận ${frame.n})`);
      this.receiveNext++;
      const plaintext = await subtle.decrypt(
        { name: "AES-GCM", iv: nonce(this.receiveTag, frame.n) },
        this.receiveKey,
        fromBase64(frame.c),
      );
      return new Uint8Array(plaintext);
    }
  }

  const api = {
    base32,
    idFromSpki,
    formatId,
    normalizeId,
    generateIdentity,
    identityFromKeys,
    importIdentity,
    relayAuth,
    startHello,
    finishHello,
    toBase64,
    fromBase64,
    ECDH,
  };
  if (typeof module === "object" && module.exports) module.exports = api;
  else globalThis.MagicSignE2E = api;
})();
