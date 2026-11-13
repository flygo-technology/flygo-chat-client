// Service worker: one authenticated connection, multiplexing plugin calls
// from every tab. It goes either to a sign server (WSS, OAuth login) or, in
// relay mode, end-to-end encrypted to an agent through the relay (relay.js).
importScripts("e2e.js", "relay.js");

const PING_INTERVAL = 20_000;
const CONNECT_WAIT = 8_000;

let socket = null;
let status = { state: "idle", user: null, error: null };
let reconnectDelay = 1_000;
let reconnectTimer = null;
let discovering = false;
let pingTimer = null;
let nextId = 1;
let revokedReason = null;
const routes = new Map(); // server id -> { port, localId, kind }
const prompts = new Map(); // prompt id -> tab showing the confirmation dialog
const vaultCalls = new Map(); // rid -> resolve, for the app's password vault
const nativeSigns = new Map(); // rid -> resolve, for programs signing through the app (PKCS#11)
const pinCalls = new Map(); // rid -> resolve, for websites pinned to a company's home page
const NATIVE_ORIGIN = "https://pkcs11.invalid";
const demoPrompts = new Set(); // sample dialogs opened from the popup, never sent to the server

// ---- debug logging -----------------------------------------------------------
// An admin switches it on per device from the server; traffic of the websites
// the user may sign on is then sent to the server in full (headers, cookies,
// bodies, WebSocket frames) for analysis.
const LOG_BUFFER_LIMIT = 5000;
const LOG_BATCH = 200;
const BODY_LIMIT = 256 * 1024;
let debugState = { until: null, origins: [] };
const logBuffer = [];
const tabOrigins = new Map(); // tab id -> top frame origin
const netRequests = new Map(); // webRequest id -> entry being built

function debugActive() {
  return !!debugState.until && Date.parse(debugState.until) > Date.now();
}

/** Same rules as the server: exact origin, `https://*.example.vn` or `*`. */
function originAllowed(origin, patterns) {
  if (!origin || origin === "null") return false;
  return patterns.some((pattern) => {
    if (pattern === "*" || pattern.toLowerCase() === origin.toLowerCase()) return true;
    const match = pattern.match(/^(https?):\/\/\*\.(.+)$/i);
    if (!match) return false;
    try {
      const url = new URL(origin);
      const host = url.hostname.toLowerCase();
      const suffix = match[2].toLowerCase();
      return url.protocol === `${match[1].toLowerCase()}:` && (host === suffix || host.endsWith(`.${suffix}`));
    } catch {
      return false;
    }
  });
}

function setDebug(message) {
  debugState = { until: message.until || null, origins: message.origins || [] };
  chrome.storage.local.set({ debug: debugState });
  if (!debugActive()) {
    logBuffer.length = 0;
    netRequests.clear();
  }
}

function pushLog(entry) {
  if (!debugActive()) return;
  logBuffer.push(entry);
  if (logBuffer.length > LOG_BUFFER_LIMIT) logBuffer.splice(0, logBuffer.length - LOG_BUFFER_LIMIT);
}

function flushLogs() {
  if (!logBuffer.length || socket?.readyState !== 1) return;
  socket.send(JSON.stringify({ t: "log", entries: logBuffer.splice(0, LOG_BATCH) }));
}
setInterval(flushLogs, 2000);

const clip = (text) => (text.length > BODY_LIMIT ? `${text.slice(0, BODY_LIMIT)}…[+${text.length - BODY_LIMIT}]` : text);

function requestBodyOf(body) {
  if (!body) return undefined;
  if (body.error) return { error: body.error };
  if (body.formData) return { formData: body.formData };
  if (body.raw) {
    const parts = body.raw.map((part) => {
      if (part.file) return `<file ${part.file}>`;
      if (!part.bytes) return "";
      return new TextDecoder("utf-8", { fatal: false }).decode(part.bytes);
    });
    return { raw: clip(parts.join("")) };
  }
  return undefined;
}

/** Whether a webRequest belongs to a tab showing a debugged website. */
function debuggedTab(details) {
  if (!debugActive() || details.tabId < 0) return false;
  const top = tabOrigins.get(details.tabId);
  return originAllowed(top, debugState.origins) || originAllowed(details.initiator, debugState.origins);
}

const NET_FILTER = { urls: ["<all_urls>"] };
chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    if (details.type === "main_frame") {
      try {
        tabOrigins.set(details.tabId, new URL(details.url).origin);
      } catch {
        /* ignore */
      }
    }
    if (!debuggedTab(details)) return;
    netRequests.set(details.requestId, {
      kind: "net",
      at: new Date(details.timeStamp).toISOString(),
      tabId: details.tabId,
      frameId: details.frameId,
      tabOrigin: tabOrigins.get(details.tabId) || null,
      initiator: details.initiator || null,
      type: details.type,
      method: details.method,
      url: details.url,
      requestBody: requestBodyOf(details.requestBody),
      started: details.timeStamp,
    });
  },
  NET_FILTER,
  ["requestBody"],
);
chrome.webRequest.onSendHeaders.addListener(
  (details) => {
    const entry = netRequests.get(details.requestId);
    if (entry) entry.requestHeaders = details.requestHeaders;
  },
  NET_FILTER,
  ["requestHeaders", "extraHeaders"],
);
chrome.webRequest.onHeadersReceived.addListener(
  (details) => {
    const entry = netRequests.get(details.requestId);
    if (!entry) return;
    entry.status = details.statusCode;
    entry.statusLine = details.statusLine;
    entry.responseHeaders = details.responseHeaders;
  },
  NET_FILTER,
  ["responseHeaders", "extraHeaders"],
);
function finishNet(details, extra) {
  const entry = netRequests.get(details.requestId);
  if (!entry) return;
  netRequests.delete(details.requestId);
  const { started, ...rest } = entry;
  pushLog({ ...rest, ...extra, ip: details.ip, fromCache: details.fromCache, ms: Math.round(details.timeStamp - started) });
}
chrome.webRequest.onCompleted.addListener((details) => finishNet(details, { status: details.statusCode }), NET_FILTER);
chrome.webRequest.onErrorOccurred.addListener((details) => finishNet(details, { error: details.error }), NET_FILTER);
chrome.tabs.onUpdated.addListener((tabId, _change, tab) => {
  if (!tab.url) return;
  try {
    tabOrigins.set(tabId, new URL(tab.url).origin);
  } catch {
    /* ignore */
  }
});
chrome.tabs.query({}).then((tabs) =>
  tabs.forEach((tab) => {
    try {
      if (tab.url) tabOrigins.set(tab.id, new URL(tab.url).origin);
    } catch {
      /* ignore */
    }
  }),
);
chrome.storage.local.get(["debug"]).then(({ debug }) => {
  if (debug) debugState = debug;
});
const waiters = [];

// Addresses tried when nothing is configured: the server publishes
// `magic-sign.local` over mDNS.
const DISCOVERY_CANDIDATES = [
  "http://magic-sign.local:7443",
  "https://magic-sign.local:7443",
  "https://magic-sign.local",
];
const OAUTH_CLIENT_ID = "magic-sign-extension";
const DISCOVERY_TIMEOUT = 20_000;
const DISCOVERY_RETRY = 60_000;

async function managed() {
  try {
    return await chrome.storage.managed.get(["serverUrl", "deviceName"]);
  } catch {
    return {};
  }
}

const trimUrl = (url) => (url || "").trim().replace(/\/+$/, "");

async function settings() {
  const policy = await managed();
  const { serverUrl = "", token = "" } = await chrome.storage.local.get(["serverUrl", "token"]);
  return { serverUrl: trimUrl(policy.serverUrl || serverUrl), token, locked: !!policy.serverUrl };
}

async function deviceIdentity() {
  const policy = await managed();
  let { deviceId, deviceName } = await chrome.storage.local.get(["deviceId", "deviceName"]);
  if (!deviceId) {
    deviceId = crypto.randomUUID();
    await chrome.storage.local.set({ deviceId });
  }
  const platform = navigator.userAgentData?.platform || navigator.platform || "máy tính";
  return { deviceId, deviceName: policy.deviceName || deviceName || `Chrome trên ${platform}` };
}

/** Find a sign server: admin policy first, then mDNS name on the LAN. */
async function discover() {
  const policy = await managed();
  if (policy.serverUrl) return { url: trimUrl(policy.serverUrl), locked: true };
  // Windows takes several seconds for the first `.local` lookup (it waits
  // for an IPv6 answer too), so wait long and try every candidate at once.
  const probe = async (candidate) => {
    const response = await fetch(`${candidate}/api/discovery`, { signal: AbortSignal.timeout(DISCOVERY_TIMEOUT) });
    const body = await response.json();
    if (body?.service !== "magic-sign") throw new Error("not a sign server");
    // The LAN name only finds the server; use its HTTPS address when it has one.
    const publicUrl = trimUrl(body.publicUrl);
    if (publicUrl) {
      const remote = await fetch(`${publicUrl}/api/discovery`, { signal: AbortSignal.timeout(8000) })
        .then((reply) => reply.json())
        .catch(() => null);
      if (remote?.service === "magic-sign") return { url: publicUrl, via: candidate, name: body.name, locked: false };
    }
    return { url: candidate, name: body.name, locked: false };
  };
  try {
    return await Promise.any(DISCOVERY_CANDIDATES.map(probe));
  } catch {
    return { url: null };
  }
}

function base64Url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** OAuth 2 authorization code + PKCE through the server's web app. */
async function login(serverUrl, deviceName, sso = false) {
  serverUrl = trimUrl(serverUrl);
  if (!/^https?:\/\//.test(serverUrl)) throw new Error("Địa chỉ máy chủ phải bắt đầu bằng http:// hoặc https://");
  if (deviceName) await chrome.storage.local.set({ deviceName: deviceName.trim() });
  const device = await deviceIdentity();
  const verifier = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64Url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
  const state = base64Url(crypto.getRandomValues(new Uint8Array(16)));
  const redirectUri = chrome.identity.getRedirectURL("oauth");
  const authorize = new URL("/oauth/authorize", serverUrl);
  authorize.search = new URLSearchParams({
    response_type: "code",
    client_id: OAUTH_CLIENT_ID,
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state,
    device_id: device.deviceId,
    device_name: device.deviceName,
    // The server's login page goes straight to its SSO (Google).
    ...(sso ? { sso: "1" } : {}),
  }).toString();

  const result = new URL(await chrome.identity.launchWebAuthFlow({ url: authorize.href, interactive: true }));
  if (result.searchParams.get("state") !== state) throw new Error("Phản hồi đăng nhập không khớp");
  const error = result.searchParams.get("error");
  if (error) throw new Error(error === "access_denied" ? "Đã từ chối đăng nhập" : error);

  const response = await fetch(`${serverUrl}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code: result.searchParams.get("code") || "",
      redirect_uri: redirectUri,
      client_id: OAUTH_CLIENT_ID,
      code_verifier: verifier,
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error_description || body.error || "Không lấy được phiên đăng nhập");
  revokedReason = null;
  await chrome.storage.local.set({
    serverUrl,
    token: body.access_token,
    username: body.user?.username || "",
    displayName: body.user?.displayName || "",
  });
  return body.user;
}

/**
 * What a page may learn about the extension. Only the sign server's own web
 * app sees the account it is connected with; other websites just learn that
 * the extension is installed.
 */
async function webStatus(origin) {
  const { serverUrl, locked } = await settings();
  const version = chrome.runtime.getManifest().version;
  if (!origin || trimUrl(serverUrl) !== origin) return { version, sameServer: false, locked, connected: false };
  return { version, sameServer: true, locked, connected: status.state === "connected", state: status.state, user: status.user || null };
}

/**
 * The web app of a sign server asks to connect this browser to itself. The
 * origin comes from Chrome, and the user still confirms on the server's
 * authorization page.
 */
async function connectFromWeb(origin) {
  if (!/^https?:\/\//.test(origin || "")) throw new Error("Trang không hợp lệ");
  const policy = await managed();
  if (policy.serverUrl && trimUrl(policy.serverUrl) !== origin) {
    throw new Error(`Trình duyệt này được quản trị cố định vào máy chủ ${new URL(policy.serverUrl).host}`);
  }
  const discovery = await fetch(`${origin}/api/discovery`, { signal: AbortSignal.timeout(8000) })
    .then((reply) => reply.json())
    .catch(() => null);
  if (discovery?.service !== "magic-sign") throw new Error("Trang này không phải máy chủ Ký số đa năng");
  return login(origin);
}

async function logout() {
  const { serverUrl, token } = await settings();
  if (serverUrl && token) {
    fetch(`${serverUrl}/api/auth/logout`, { method: "POST", headers: { Authorization: `Bearer ${token}` } }).catch(() => {});
  }
  await chrome.storage.local.remove(["token", "username", "displayName", "serverCatalog"]);
  setDebug({ until: null, origins: [] });
}

function setStatus(next) {
  status = { ...status, ...next };
  chrome.action.setBadgeText({ text: status.state === "connected" ? "" : "!" });
  chrome.action.setBadgeBackgroundColor({ color: "#c42b1c" });
}

// ---- relay mode ---------------------------------------------------------------
// The relay and the connect page are fixed: agents and their settings only
// reach the extension from ky.flygo.vn (connect links), never typed in.
const CONNECT_ORIGIN = "https://ky.flygo.vn";
const accessWaiters = []; // resolved with the agent's answer to a connect request

async function relaySettings() {
  const { agents = [] } = await chrome.storage.local.get(["agents"]);
  return { relayUrl: MagicSignRelay.DEFAULT_RELAY, agent: agents[0] || null, agents };
}

async function updateAgent(agentId, changes) {
  const { agents = [] } = await chrome.storage.local.get(["agents"]);
  const next = agents.map((agent) => (agent.agentId === agentId ? { ...agent, ...changes } : agent));
  await chrome.storage.local.set({ agents: next });
}

/** The agent answered (welcome, pending, invalid_invite, revoked, catalog). */
function onAccess(agentId, state, message) {
  if (state === "catalog") {
    void updateAgent(agentId, { catalog: message.tokens, catalogAt: new Date().toISOString(), name: message.agentName || undefined });
    return;
  }
  if (state === "welcome") void updateAgent(agentId, { invite: null, name: message.agentName, grantedAt: new Date().toISOString() });
  const errors = {
    pending: "Đang chờ quản trị viên duyệt thiết bị này",
    invalid_invite: "Link kết nối đã hết hạn hoặc đã được dùng, hãy xin link mới",
    revoked: "Quyền ký của thiết bị này đã hết hạn hoặc bị thu hồi",
  };
  if (state === "invalid_invite") void updateAgent(agentId, { invite: null });
  if (errors[state]) setStatus({ state: state === "pending" ? "pending" : "denied", error: errors[state] });
  accessWaiters.splice(0).forEach((resolve) => resolve({ ok: state === "welcome", state, agentName: message.agentName }));
}

/** Connect page: remember the agent (first in the list) and connect. */
async function addAgent(agentId, invite, deviceName) {
  const id = MagicSignE2E.normalizeId(agentId);
  if (!id) throw new Error("Agent ID không hợp lệ");
  // The admin approves people, not browsers: a name is required to connect.
  const name = String(deviceName || "").trim().slice(0, 64);
  if (name.length < 2) throw new Error("Hãy nhập tên của bạn trước khi kết nối");
  await chrome.storage.local.set({ deviceName: name });
  const { agents = [] } = await chrome.storage.local.get(["agents"]);
  const previous = agents.find((agent) => agent.agentId === id);
  const entry = { ...previous, agentId: id, invite: invite || previous?.invite || null, addedAt: previous?.addedAt || new Date().toISOString() };
  await chrome.storage.local.set({ agents: [entry, ...agents.filter((agent) => agent.agentId !== id)] });
  socket?.close();
  socket = null;
  reconnectDelay = 1_000;
  const answer = new Promise((resolve) => {
    accessWaiters.push(resolve);
    setTimeout(() => resolve({ ok: false, state: "timeout" }), 30_000);
  });
  void connect();
  return answer;
}

// ---- agents on the LAN ------------------------------------------------------
// An agent may answer `/api/discovery` on the office network (installer
// option `--discovery-listen`). The search runs in the background; the popup
// shows a "Kết nối" link, which joins without an invite and waits for the
// admin to approve the browser, and, when the server has SSO, a Google login
// that needs no approval.
const LAN_CANDIDATES = ["http://magic-sign.local:7444", "http://magic-sign.local:7443"];
const LAN_SCAN_MINUTES = 15;

async function scanLan() {
  const probe = async (base) => {
    const response = await fetch(`${base}/api/discovery`, { signal: AbortSignal.timeout(DISCOVERY_TIMEOUT) });
    const body = await response.json();
    const publicUrl = trimUrl(body?.publicUrl || "");
    const sso = !!body?.sso && /^https:\/\//.test(publicUrl);
    if (body?.service !== "magic-sign" || (!body.agent?.id && !sso)) throw new Error("not an agent");
    return { agentId: body.agent?.id || null, name: body.agent?.name || body.name || null, via: base, publicUrl, sso };
  };
  const found = await Promise.any(LAN_CANDIDATES.map(probe)).catch(() => null);
  const { agents = [] } = await chrome.storage.local.get(["agents"]);
  // Not when already using it: as a relay agent, or as the server this
  // browser is logged in to.
  const { serverUrl, token } = await settings();
  const sameServer = found?.publicUrl && token && found.publicUrl === serverUrl;
  const lanAgent = found && !sameServer && !agents.some((agent) => agent.agentId && agent.agentId === found.agentId) ? found : null;
  await chrome.storage.local.set({ lanAgent });
  return lanAgent;
}


/** One `vault_call` to the connected agent; resolves to `{result}` or `{error}`. */
async function vaultCall(op, args) {
  if (socket?.readyState !== 1 || status.state !== "connected") {
    const ready = new Promise((resolve) => waiters.push(resolve));
    void connect();
    await Promise.race([ready, new Promise((resolve) => setTimeout(resolve, 15_000))]);
  }
  if (socket?.readyState !== 1) return { error: "Chưa kết nối được agent" };
  const rid = nextId++;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      vaultCalls.delete(rid);
      resolve({ error: "Agent không trả lời" });
    }, 30_000);
    vaultCalls.set(rid, (message) => {
      clearTimeout(timer);
      resolve(message.error != null ? { error: message.error } : { result: message.result });
    });
    socket.send(JSON.stringify({ t: "vault_call", rid, op, args: args || {} }));
  });
}

/**
 * Sign a SHA-256 (or SHA-1) digest for a program on this machine (the app's PKCS#11 /
 * Windows CSP bridge). The agent applies this device's rules for
 * NATIVE_ORIGIN; the app has already asked the user.
 */
async function nativeSign(tokenId, digest, application, algorithm = "sha256") {
  if (socket?.readyState !== 1 || status.state !== "connected") {
    const ready = new Promise((resolve) => waiters.push(resolve));
    void connect();
    await Promise.race([ready, new Promise((resolve) => setTimeout(resolve, 15_000))]);
  }
  if (socket?.readyState !== 1) return { error: { code: "device_error", message: "Chưa kết nối được máy ký" } };
  const rid = nextId++;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      nativeSigns.delete(rid);
      resolve({ error: { code: "device_error", message: "Máy ký không trả lời" } });
    }, 120_000);
    nativeSigns.set(rid, (message) => {
      clearTimeout(timer);
      resolve(message.error ? { error: message.error } : { signature: message.signature, algorithm: message.algorithm });
    });
    socket.send(
      JSON.stringify({
        t: "sign_digest",
        rid,
        tokenId,
        origin: NATIVE_ORIGIN,
        pageUrl: null,
        digest,
        algorithm: algorithm === "sha1" ? "sha1" : "sha256",
        description: `Ký từ ứng dụng ${String(application || "trên máy tính").slice(0, 80)}`,
      }),
    );
  });
}

/**
 * Pin a website to a token's home page in the apps, or unpin it. The agent
 * sends every device using the token a new catalog with the pins.
 */
async function setPin(tokenId, url, title, remove) {
  if (socket?.readyState !== 1 || status.state !== "connected") {
    const ready = new Promise((resolve) => waiters.push(resolve));
    void connect();
    await Promise.race([ready, new Promise((resolve) => setTimeout(resolve, 15_000))]);
  }
  if (socket?.readyState !== 1) return { error: "Chưa kết nối được máy ký" };
  const rid = nextId++;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pinCalls.delete(rid);
      resolve({ error: "Máy ký không trả lời" });
    }, 15_000);
    pinCalls.set(rid, (message) => {
      clearTimeout(timer);
      resolve(message.error ? { error: message.error } : { ok: true });
    });
    socket.send(JSON.stringify({ t: "pin_set", rid, tokenId, url, title, remove: !!remove }));
  });
}

async function connect() {
  if (socket && socket.readyState <= 1) return;
  clearTimeout(reconnectTimer);
  const relay = await relaySettings();
  if (relay.agent) return openSocket(relay);
  let { serverUrl, token } = await settings();
  if (!serverUrl) {
    // Nothing configured yet: look for a server on the LAN right away and
    // remember it, so the user only has to log in.
    // Startup, install and storage events all call connect(); search once.
    if (discovering) return;
    discovering = true;
    setStatus({ state: "discovering", user: null, error: "Đang tìm máy chủ ký trong mạng…" });
    const found = await discover().finally(() => (discovering = false));
    // An agent may have been added from a connect link during the search.
    if ((await relaySettings()).agent) return connect();
    if (found.url) {
      serverUrl = found.url;
      await chrome.storage.local.set({ serverUrl });
    } else {
      // Not on the office network yet (or the server is down): keep looking.
      // An alarm, not a timer: Chrome stops idle extension workers after
      // about 30 seconds and timers die with them.
      chrome.alarms.create("discover", { delayInMinutes: DISCOVERY_RETRY / 60_000 });
    }
  }
  if (!serverUrl || !token) {
    // Keep the reason when the session was just revoked.
    const error =
      revokedReason ||
      (serverUrl ? `Đã tìm thấy máy chủ ${new URL(serverUrl).host}, hãy đăng nhập` : "Chưa tìm thấy máy chủ ký trong mạng");
    setStatus({ state: "unconfigured", user: null, error, serverUrl: serverUrl || null });
    return;
  }
  return openSocket({ serverUrl, token });
}

/** Open the server WebSocket, or a RelaySocket when `relay.agent` is set. */
async function openSocket({ serverUrl, token, agent, relayUrl }) {
  setStatus({ state: "connecting", error: null, serverUrl: serverUrl || null, agent: agent ? { agentId: agent.agentId, name: agent.name || null } : null });
  let current;
  if (agent) {
    const { deviceName } = await deviceIdentity();
    current = new MagicSignRelay.RelaySocket(agent.agentId, {
      relayUrl,
      invite: agent.invite,
      deviceName,
      onAccess: (state, message) => onAccess(agent.agentId, state, message),
    });
  } else {
    const url = new URL("/api/relay", serverUrl);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.searchParams.set("token", token);
    url.searchParams.set("v", chrome.runtime.getManifest().version);
    current = new WebSocket(url);
  }
  socket = current;
  let greeted = false;

  current.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.t === "catalog") {
      // Server mode: tokens this user may use (relay mode keeps them per agent).
      void chrome.storage.local.set({
        serverCatalog: { agentName: message.agentName || null, tokens: message.tokens || [], at: new Date().toISOString() },
      });
      return;
    }
    if (message.t === "hello") {
      greeted = true;
      reconnectDelay = 1_000;
      setStatus({ state: "connected", user: message.user, error: null });
      chrome.storage.local.set({ ports: message.ports });
      setDebug({ until: null, origins: [] }); // the server sends the real state next
      waiters.splice(0).forEach((resolve) => resolve(true));
      return;
    }
    if (message.t === "pong") return;
    if (message.t === "vault_res") {
      vaultCalls.get(message.rid)?.(message);
      vaultCalls.delete(message.rid);
      return;
    }
    if (message.t === "pin_res") {
      pinCalls.get(message.rid)?.(message);
      pinCalls.delete(message.rid);
      return;
    }
    if (message.t === "sign_res") {
      nativeSigns.get(message.rid)?.(message);
      nativeSigns.delete(message.rid);
      return;
    }
    if (message.t === "debug") return setDebug(message);
    if (message.t === "prompt") return showPrompt(message);
    if (message.t === "prompt_state" || message.t === "prompt_close") return forwardPrompt(message);
    const route = routes.get(message.id);
    if (!route) return;
    if (message.t === "http_res" || message.t === "ws_closed") routes.delete(message.id);
    try {
      route.port.postMessage({ ...message, id: route.localId });
    } catch {
      routes.delete(message.id);
    }
  };

  current.onclose = async (event) => {
    if (socket === current) {
      for (const done of vaultCalls.values()) done({ error: "Mất kết nối agent" });
      vaultCalls.clear();
    }
    if (socket !== current) return;
    socket = null;
    clearInterval(pingTimer);
    for (const pid of [...prompts.keys()]) forwardPrompt({ t: "prompt_close", pid });
    // Fail everything that was in flight on this connection.
    for (const [id, route] of routes) {
      const failure =
        route.kind === "http"
          ? { t: "http_res", id: route.localId, error: "mất kết nối máy chủ ký" }
          : { t: "ws_closed", id: route.localId, code: 1006, reason: "mất kết nối máy chủ ký" };
      try {
        route.port.postMessage(failure);
      } catch {
        /* tab gone */
      }
      routes.delete(id);
    }
    // Refused by the agent: retrying cannot help until something changes.
    if (agent && event.code === 4003) return;
    // A WebSocket hides the HTTP status; ask the API whether the session
    // was revoked or expired before retrying forever.
    if (!greeted && !agent) {
      const me = await fetch(`${serverUrl}/api/me`, { headers: { Authorization: `Bearer ${token}` } }).catch(() => null);
      if (me?.status === 401) {
        revokedReason = "Phiên đăng nhập đã hết hạn hoặc bị thu hồi, hãy đăng nhập lại";
        await chrome.storage.local.remove(["token"]);
        return;
      }
    }
    setStatus({ state: "disconnected", error: greeted ? "Mất kết nối" : event.reason || "Không kết nối được máy chủ" });
    reconnectTimer = setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 2, 30_000);
  };

  clearInterval(pingTimer);
  pingTimer = setInterval(() => {
    if (current.readyState === 1) current.send(JSON.stringify({ t: "ping" }));
  }, PING_INTERVAL);
}

function replyPrompt(pid, answer) {
  if (demoPrompts.delete(pid)) {
    // Let the user see the "signing" state, then close the sample.
    setTimeout(() => forwardPrompt({ t: "prompt_close", pid }), 1500);
    return;
  }
  if (socket?.readyState === 1) socket.send(JSON.stringify({ t: "prompt_reply", pid, ...answer }));
}

/** Show the server's confirmation dialog in the tab that made the request. */
function showPrompt(message) {
  const { t: _type, rid, ...prompt } = message;
  const tabId = routes.get(rid)?.port.sender?.tab?.id;
  if (tabId === undefined) return replyPrompt(prompt.pid, { error: "tab_unavailable" });
  prompts.set(prompt.pid, tabId);
  chrome.tabs.sendMessage(tabId, { t: "magic-sign:prompt", prompt }, { frameId: 0 }).catch(() => {
    // Page loaded before the extension: let an approver handle it.
    prompts.delete(prompt.pid);
    replyPrompt(prompt.pid, { error: "tab_unavailable" });
  });
}

function forwardPrompt(message) {
  const tabId = prompts.get(message.pid);
  if (tabId === undefined) return;
  if (message.t === "prompt_close") prompts.delete(message.pid);
  chrome.tabs.sendMessage(tabId, { ...message, t: `magic-sign:${message.t}` }, { frameId: 0 }).catch(() => {});
}

/** Sample dialog on the active tab, to show users what to expect. */
async function demoPrompt() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  let origin;
  try {
    origin = new URL(tab?.url || "").origin;
  } catch {
    origin = "null";
  }
  if (!tab || !/^https?:/.test(origin)) return { ok: false, error: "Hãy mở một trang web (http/https) rồi thử lại" };
  const pid = `demo-${crypto.randomUUID()}`;
  const year = new Date().getFullYear();
  const prompt = {
    pid,
    title: "Ký tờ khai thuế (VÍ DỤ)",
    description: "Đây là hộp xác nhận mẫu, không có gì được ký.",
    origin,
    pageUrl: tab.url,
    action: "NTDT_CER_001",
    digest: "3F6C1A9E".repeat(8),
    requirePin: true,
    requested: null,
    certificates: [
      { tokenId: "demo-a", company: "CÔNG TY MẪU A", taxCode: "0100000001", serial: "540101019D89635B", provider: "MISA-CA", notAfter: `${year + 1}-06-30T00:00:00Z`, matchesRequest: null, needsApprover: false },
      { tokenId: "demo-b", company: "CÔNG TY MẪU B", taxCode: "0100000002", serial: "5401010177220B33", provider: "FPT-CA", notAfter: `${year + 2}-01-31T00:00:00Z`, matchesRequest: null, needsApprover: true },
    ],
    warnings: [
      { level: "warning", text: "Website này không gửi thông tin chứng thư cần ký. Hãy kiểm tra kỹ tên công ty và mã số thuế trước khi xác nhận." },
      { level: "info", text: "Đây là hộp mẫu từ nút \"Xem thử\" của extension." },
    ],
  };
  demoPrompts.add(pid);
  prompts.set(pid, tab.id);
  try {
    await chrome.tabs.sendMessage(tab.id, { t: "magic-sign:prompt", prompt }, { frameId: 0 });
    return { ok: true };
  } catch {
    demoPrompts.delete(pid);
    prompts.delete(pid);
    return { ok: false, error: "Trang này mở trước khi cài extension, hãy tải lại trang rồi thử" };
  }
}

chrome.tabs.onRemoved.addListener((tabId) => {
  for (const [pid, owner] of prompts) {
    if (owner !== tabId) continue;
    prompts.delete(pid);
    replyPrompt(pid, { approved: false });
  }
});

function connected() {
  if (socket?.readyState === 1 && status.state === "connected") return Promise.resolve(true);
  void connect();
  return new Promise((resolve) => {
    waiters.push(resolve);
    setTimeout(() => resolve(false), CONNECT_WAIT);
  });
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "magic-sign") return;
  const origin = port.sender?.origin;
  const pageUrl = port.sender?.url;
  const owned = new Set();

  port.onMessage.addListener(async (message) => {
    if (message.t === "log") {
      // The origin comes from Chrome, not from the page.
      if (originAllowed(origin, debugState.origins)) {
        pushLog({ ...message.entry, origin, pageUrl: port.sender?.url, tabId: port.sender?.tab?.id, frameId: port.sender?.frameId });
      }
      return;
    }
    const ok = await connected();
    if (!ok) {
      const error = status.error || "Chưa kết nối máy chủ ký";
      if (message.t === "http") port.postMessage({ t: "http_res", id: message.id, error });
      if (message.t === "ws_open") port.postMessage({ t: "ws_closed", id: message.id, code: 1006, reason: error });
      return;
    }
    let id;
    if (message.t === "http" || message.t === "ws_open") {
      id = nextId++;
      routes.set(id, { port, localId: message.id, kind: message.t === "http" ? "http" : "ws" });
      owned.add(id);
      socket.send(JSON.stringify({ ...message, id, origin, pageUrl }));
      return;
    }
    // ws_send / ws_close refer to an existing socket of this port.
    for (const [serverId, route] of routes) {
      if (route.port === port && route.localId === message.id && route.kind === "ws") id = serverId;
    }
    if (id !== undefined) socket.send(JSON.stringify({ ...message, id }));
  });

  port.onDisconnect.addListener(() => {
    for (const id of owned) {
      const route = routes.get(id);
      if (route?.kind === "ws" && socket?.readyState === 1) socket.send(JSON.stringify({ t: "ws_close", id }));
      routes.delete(id);
    }
  });
});

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message?.t === "prompt_reply") {
    // Only the tab that shows the dialog may answer it.
    if (sender.tab?.id !== undefined && prompts.get(message.pid) === sender.tab.id) {
      replyPrompt(message.pid, { approved: !!message.approved, tokenId: message.tokenId || null });
    }
    return false;
  }
  if (message?.t === "relay_status" || message?.t === "relay_connect") {
    // Only the official connect page may add agents or see them.
    (async () => {
      if (sender.origin !== CONNECT_ORIGIN) return reply({ ok: false, error: "Trang này không được phép" });
      if (message.t === "relay_connect") {
        return addAgent(message.agentId, message.invite, message.deviceName).then(reply, (error) =>
          reply({ ok: false, error: error.message }),
        );
      }
      const [extensionId, relay] = await Promise.all([MagicSignRelay.extensionId(), relaySettings()]);
      // Only a name the user typed (or the admin set), not the default one.
      const { deviceName = "" } = await chrome.storage.local.get(["deviceName"]);
      const policy = await managed();
      reply({
        ok: true,
        version: chrome.runtime.getManifest().version,
        extensionId,
        deviceName: policy.deviceName || deviceName,
        state: status.state,
        agents: relay.agents.map(({ agentId, name, grantedAt }) => ({ agentId, name, grantedAt })),
      });
    })();
    return true;
  }
  if (message?.t === "web_status") {
    webStatus(sender.origin).then(reply);
    return true;
  }
  if (message?.t === "web_connect") {
    connectFromWeb(sender.origin).then(
      (user) => reply({ ok: true, user }),
      (error) => reply({ ok: false, error: error.message }),
    );
    return true;
  }
  if (message?.t === "demo_prompt") {
    demoPrompt().then(reply);
    return true;
  }
  if (message?.t === "status") {
    // Opening the popup retries the search right away.
    if (status.state === "unconfigured" && !status.serverUrl) void connect();
    reply(status);
  } else if (message?.t === "discover") {
    discover().then(reply);
    return true;
  } else if (message?.t === "login") {
    login(message.serverUrl, message.deviceName, !!message.sso).then(
      (user) => reply({ ok: true, user }),
      (error) => reply({ ok: false, error: error.message }),
    );
    return true;
  } else if (message?.t === "logout") {
    logout().then(() => reply({ ok: true }));
    return true;
  } else if (message?.t === "device") {
    Promise.all([deviceIdentity(), MagicSignRelay.extensionId().catch((error) => null), relaySettings()])
      .then(([device, extensionId, relay]) => reply({ ...device, extensionId, agents: relay.agents }))
      .catch((error) => reply({ error: error.message }));
    return true;
  } else if (message?.t === "remove_agent") {
    chrome.storage.local.get(["agents"]).then(async ({ agents = [] }) => {
      await chrome.storage.local.set({ agents: agents.filter((agent) => agent.agentId !== message.agentId) });
      socket?.close();
      socket = null;
      void connect().then(() => reply({ ok: true }));
    });
    return true;
  } else if (message?.t === "refresh_catalog") {
    // The answer arrives as a `catalog` message and lands in storage.
    if (socket?.readyState === 1) {
      socket.send(JSON.stringify({ t: "catalog_get" }));
      reply({ ok: true });
    } else {
      reply({ ok: false, error: "Chưa kết nối, đang dùng danh sách đã lưu" });
    }
    return false;
  } else if (message?.t === "lan_scan") {
    scanLan().then((lanAgent) => reply({ lanAgent }));
    return true;
  } else if (message?.t === "vault") {
    // The apps' password vault; only their own pages, never a website.
    if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) {
      reply({ error: "Không được phép" });
      return false;
    }
    vaultCall(message.op, message.args).then(reply);
    return true;
  } else if (message?.t === "native_sign") {
    // Only the app itself (its PKCS#11 bridge), never a website.
    if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) {
      reply({ error: { code: "permission_denied", message: "Không được phép" } });
      return false;
    }
    nativeSign(String(message.tokenId || ""), String(message.digest || ""), message.application, message.algorithm).then(reply);
    return true;
  } else if (message?.t === "pin_set") {
    // Only the apps' own pages, never a website.
    if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) {
      reply({ error: "Không được phép" });
      return false;
    }
    setPin(String(message.tokenId || ""), String(message.url || ""), String(message.title || ""), message.remove).then(reply);
    return true;
  } else if (message?.t === "lan_login") {
    // Google login on the office server found on the LAN; own pages only.
    if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) {
      reply({ ok: false, error: "Không được phép" });
      return false;
    }
    chrome.storage.local.get(["lanAgent"]).then(async ({ lanAgent }) => {
      if (!lanAgent?.sso) return reply({ ok: false, error: "Không còn thấy máy chủ ký trong mạng" });
      login(lanAgent.publicUrl, message.deviceName, true).then(
        async (user) => {
          await chrome.storage.local.set({ lanAgent: null });
          reply({ ok: true, user });
        },
        (error) => reply({ ok: false, error: error.message }),
      );
    });
    return true;
  } else if (message?.t === "lan_request") {
    // Only the extension's own pages, never a website.
    if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) {
      reply({ ok: false, error: "Không được phép" });
      return false;
    }
    chrome.storage.local.get(["lanAgent"]).then(async ({ lanAgent }) => {
      if (!lanAgent) return reply({ ok: false, error: "Không còn thấy agent trong mạng" });
      if (String(message.deviceName || "").trim().length < 2) {
        return reply({ ok: false, error: "Hãy nhập tên của bạn trước khi kết nối" });
      }
      await chrome.storage.local.set({ lanAgent: null });
      addAgent(lanAgent.agentId, null, message.deviceName).then(reply, (error) => reply({ ok: false, error: error.message }));
    });
    return true;
  } else if (message?.t === "reconnect") {
    socket?.close();
    socket = null;
    reconnectDelay = 1_000;
    void connect().then(() => reply(status));
    return true;
  }
  return false;
});

chrome.storage.onChanged.addListener((changes, area) => {
  if ((area === "local" || area === "managed") && (changes.serverUrl || changes.token)) {
    socket?.close();
    socket = null;
    void connect();
  }
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "discover") void connect();
  if (alarm.name === "lan-scan") void scanLan();
});
chrome.alarms.create("lan-scan", { delayInMinutes: 0.2, periodInMinutes: LAN_SCAN_MINUTES });
chrome.runtime.onStartup.addListener(() => void connect());
chrome.runtime.onInstalled.addListener(() => void connect());
void connect();
