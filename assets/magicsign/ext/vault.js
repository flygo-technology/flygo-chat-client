// Password vault crypto (docs/vault.md). The server stores only what these
// functions produce; keys and passwords stay on devices. Used by the apps
// (device and admin side) and by Node tests (vault.test.mjs).
(() => {
  "use strict";
  const subtle = globalThis.crypto.subtle;
  const ECDH = { name: "ECDH", namedCurve: "P-256" };
  const text = new TextEncoder();
  const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

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

  const random = (length) => globalThis.crypto.getRandomValues(new Uint8Array(length));

  /** Shown on the device and recomputed by the admin's app before approving. */
  async function fingerprint(spki) {
    const digest = new Uint8Array(await subtle.digest("SHA-256", spki));
    return base32(digest.slice(0, 10));
  }

  const formatFingerprint = (value) => value.match(/.{1,4}/g).join("-");

  /**
   * A new device key. `extractable` is for the apps, which keep the private
   * key encrypted by the operating system (Windows Hello, Touch ID, Keystore)
   * rather than in a browser key store.
   */
  async function generateDeviceKey(extractable = true) {
    const keys = await subtle.generateKey(ECDH, extractable, ["deriveBits"]);
    const spki = new Uint8Array(await subtle.exportKey("spki", keys.publicKey));
    return { privateKey: keys.privateKey, publicKey: toBase64(spki), fingerprint: await fingerprint(spki) };
  }

  const exportPrivate = async (key) => subtle.exportKey("jwk", key);
  const importPrivate = (jwk) => subtle.importKey("jwk", jwk, ECDH, false, ["deriveBits"]);

  async function hkdf(secret, salt, info) {
    const material = await subtle.importKey("raw", secret, "HKDF", false, ["deriveKey"]);
    return subtle.deriveKey(
      { name: "HKDF", hash: "SHA-256", salt, info: text.encode(info) },
      material,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
  }

  const wrapAad = (tokenId, version) => text.encode(`MSV1-wrap|${tokenId}|${version}`);
  const dataAad = (tokenId, version) => text.encode(`MSV1-data|${tokenId}|${version}`);

  async function seal(key, plaintext, aad) {
    const iv = random(12);
    const ciphertext = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv, additionalData: aad }, key, plaintext));
    return concat(iv, ciphertext);
  }

  async function unseal(key, sealed, aad) {
    return new Uint8Array(
      await subtle.decrypt({ name: "AES-GCM", iv: sealed.slice(0, 12), additionalData: aad }, key, sealed.slice(12)),
    );
  }

  /** A token key: 32 random bytes, only ever sent wrapped. */
  const newTokenKey = () => random(32);

  /** Wrap a token key for a device: ephemeral ECDH, HKDF, AES-GCM. */
  async function wrapForDevice(tokenKey, devicePublicKey, tokenId, version) {
    const spki = fromBase64(devicePublicKey);
    const device = await subtle.importKey("spki", spki, ECDH, false, []);
    const eph = await subtle.generateKey(ECDH, true, ["deriveBits"]);
    const ephRaw = new Uint8Array(await subtle.exportKey("raw", eph.publicKey));
    const shared = new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: device }, eph.privateKey, 256));
    const kek = await hkdf(shared, concat(ephRaw, spki), "MSV1 device wrap");
    return toBase64(concat(ephRaw, await seal(kek, tokenKey, wrapAad(tokenId, version))));
  }

  async function unwrapForDevice(wrapped, privateKey, devicePublicKey, tokenId, version) {
    const bytes = fromBase64(wrapped);
    const ephRaw = bytes.slice(0, 65);
    const eph = await subtle.importKey("raw", ephRaw, ECDH, false, []);
    const shared = new Uint8Array(await subtle.deriveBits({ name: "ECDH", public: eph }, privateKey, 256));
    const kek = await hkdf(shared, concat(ephRaw, fromBase64(devicePublicKey)), "MSV1 device wrap");
    return unseal(kek, bytes.slice(65), wrapAad(tokenId, version));
  }

  /** 26 base32 characters (130 bits), printed once for the admin. */
  const newRecoveryCode = () => base32(random(17)).slice(0, 26);
  const normalizeRecoveryCode = (code) => String(code || "").replace(/[\s-]/g, "").toUpperCase();

  const recoveryKek = (code) =>
    hkdf(text.encode(normalizeRecoveryCode(code)), text.encode("MSV1 recovery salt"), "MSV1 recovery wrap");

  async function wrapForRecovery(tokenKey, code, tokenId, version) {
    return toBase64(await seal(await recoveryKek(code), tokenKey, wrapAad(tokenId, version)));
  }

  async function unwrapForRecovery(wrapped, code, tokenId, version) {
    return unseal(await recoveryKek(code), fromBase64(wrapped), wrapAad(tokenId, version));
  }

  const dataKey = (tokenKey) => subtle.importKey("raw", tokenKey, "AES-GCM", false, ["encrypt", "decrypt"]);

  /**
   * Entries of one token:
   * `[{ id, origin, loginUrl, username, password, blockedUrls: [] }]`.
   */
  async function encryptEntries(tokenKey, entries, tokenId, version) {
    const json = text.encode(JSON.stringify({ v: 1, entries }));
    return toBase64(await seal(await dataKey(tokenKey), json, dataAad(tokenId, version)));
  }

  async function decryptEntries(tokenKey, data, tokenId, version) {
    const json = await unseal(await dataKey(tokenKey), fromBase64(data), dataAad(tokenId, version));
    return JSON.parse(new TextDecoder().decode(json)).entries;
  }

  const api = {
    fingerprint,
    formatFingerprint,
    generateDeviceKey,
    exportPrivate,
    importPrivate,
    newTokenKey,
    wrapForDevice,
    unwrapForDevice,
    newRecoveryCode,
    wrapForRecovery,
    unwrapForRecovery,
    encryptEntries,
    decryptEntries,
    toBase64,
    fromBase64,
  };
  if (typeof module === "object" && module.exports) module.exports = api;
  else globalThis.MagicSignVault = api;
})();
