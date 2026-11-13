const $ = (id) => document.getElementById(id);
const send = (message) => chrome.runtime.sendMessage(message);
let signedIn = false;
let agent = null;

const STATES = {
  connected: ["Đã kết nối", "ok"],
  connecting: ["Đang kết nối", "wait"],
  discovering: ["Đang tìm", "wait"],
  pending: ["Chờ duyệt", "wait"],
  denied: ["Bị từ chối", "bad"],
};

function say(text) {
  $("message").textContent = text || "";
}

async function render() {
  const { enabled = true, serverUrl = "", token = "", displayName = "", username = "", lanAgent = null, serverCatalog = null } =
    await chrome.storage.local.get(["enabled", "serverUrl", "token", "displayName", "username", "lanAgent", "serverCatalog"]);
  const status = (await send({ t: "status" })) || {};
  const device = (await send({ t: "device" })) || {};
  agent = device.agents?.[0] || null;
  signedIn = !!token;

  $("version").textContent = `Phiên bản ${chrome.runtime.getManifest().version}`;
  showEnabled(enabled);
  $("device-id").textContent = device.extensionId || "đang tạo…";
  // The key is created on first use; ask again shortly.
  if (!device.extensionId) setTimeout(render, 1500);

  const [label, tone] = STATES[status.state] || ["Chưa kết nối", "bad"];
  $("state").textContent = label;
  $("state").className = `pill ${tone}`;
  const connected = status.state === "connected";

  if (agent) {
    // Relay mode: the agent grants access; there is nothing to log in to.
    $("mode-label").textContent = "Agent qua relay";
    $("title").textContent = agent.name || agent.agentId;
    $("who").textContent = connected
      ? `Đang dùng token của ${agent.name || "agent"} · ${(agent.catalog || []).length} token`
      : status.error || "Đang kết nối tới agent…";
    $("primary").hidden = true;
    $("disconnect").hidden = false;
  } else {
    $("mode-label").textContent = "Máy chủ ký";
    $("title").textContent = serverUrl ? new URL(serverUrl).host : "Chưa kết nối";
    $("who").textContent = signedIn
      ? `Đăng nhập: ${status.user?.displayName || displayName || username}`
      : status.error || "Mở link kết nối quản trị viên gửi, hoặc đăng nhập máy chủ.";
    $("primary").hidden = false;
    $("primary").textContent = signedIn ? "Mở trang ký" : "Đăng nhập";
    $("disconnect").hidden = true;
  }

  // A sign agent found on the office network: only a "Kết nối" link.
  $("lan-connect").hidden = !!agent || !lanAgent?.agentId;
  if (lanAgent) $("lan-connect").title = `Có máy ký trong mạng: ${lanAgent.name || lanAgent.agentId}`;
  // With SSO on that server, a Google login needs no admin approval.
  $("lan-google").hidden = !!agent || signedIn || !lanAgent?.sso;
  if (lanAgent?.sso) $("lan-google").title = `Đăng nhập máy chủ ký ${lanAgent.name || new URL(lanAgent.publicUrl).host}`;

  const holder = agent ? agent.name || "Agent" : serverCatalog?.agentName || (serverUrl ? new URL(serverUrl).host : "");
  const tokens = agent ? agent.catalog || [] : signedIn ? serverCatalog?.tokens || [] : [];
  const at = agent ? agent.catalogAt : serverCatalog?.at;
  renderTokens(tokens, holder);
  showAlert(enabled, status, tokens);
  // Follow a connection in progress until it settles.
  clearTimeout(render.timer);
  if (["connecting", "discovering"].includes(status.state)) render.timer = setTimeout(render, 2000);
  $("tokens-at").textContent = at ? `Cập nhật ${new Date(at).toLocaleTimeString("vi-VN")} ${new Date(at).toLocaleDateString("vi-VN")}` : "";
}

/** Why website signing will fail right now, in plain words. */
function showAlert(enabled, status, tokens) {
  let alert = null; // [title, detail, tone]
  if (!enabled) alert = null;
  else if (status.state === "connected") {
    if (!tokens.length) alert = ["Chưa có token để ký", "Đã kết nối nhưng quản trị viên chưa cấp token nào cho bạn. Hãy báo quản trị viên."];
  } else if (status.state === "pending") alert = ["Đang chờ duyệt", "Quản trị viên chưa duyệt yêu cầu kết nối, nên chưa ký được.", "wait"];
  else if (status.state === "connecting") alert = ["Đang kết nối máy ký…", "", "wait"];
  else if (agent) alert = ["Chưa kết nối token", `Không kết nối được tới ${agent.name || "agent"}: ${status.error || "mất kết nối"}. Lệnh ký của website sẽ báo lỗi.`];
  else alert = ["Chưa kết nối token", "Lệnh ký của website sẽ báo lỗi. Mở link kết nối quản trị viên gửi (ky.flygo.vn/c/…), hoặc bấm Đăng nhập."];
  const box = $("alert");
  box.hidden = !alert;
  if (!alert) return;
  const [title, detail, tone] = alert;
  const head = document.createElement("strong");
  head.textContent = title;
  const body = document.createElement("span");
  body.textContent = detail;
  box.replaceChildren(head, ...(detail ? [body] : []));
  box.className = tone ? `alert ${tone}` : "alert";
}

/** Ask the agent or server for the token list; the cached one shows meanwhile. */
async function reloadTokens(manual = false) {
  const button = $("reload");
  button.classList.add("spinning");
  const result = await send({ t: "refresh_catalog" });
  if (!result?.ok) {
    button.classList.remove("spinning");
    if (manual && result?.error) say(result.error);
    return;
  }
  // The new list lands in storage; stop spinning then, or after 5 s.
  setTimeout(() => button.classList.remove("spinning"), 5000);
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && (changes.agents || changes.serverCatalog)) {
    $("reload").classList.remove("spinning");
    render();
  }
});

const ICONS = {
  company: "M3 21h18M5 21V7l7-4 7 4v14M9 9h1m4 0h1M9 13h1m4 0h1M10 21v-4h4v4",
  tax: "M7 3h10l2 2v16H5V5zM9 8h6M9 12h6M9 16h4",
  holder: "M3 5h18v10H3zM8 19h8M12 15v4",
  access: "M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0",
  certificate: "M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6zM9 12l2 2 4-4",
};

function line(icon, text, tone) {
  const row = document.createElement("span");
  row.className = tone ? `token-line ${tone}` : "token-line";
  row.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[icon]}"/></svg>`;
  const label = document.createElement("span");
  label.textContent = text;
  row.append(label);
  return row;
}

const day = (value) => new Date(value).toLocaleDateString("vi-VN");

function renderTokens(tokens, holder) {
  const list = $("tokens");
  list.replaceChildren(
    ...tokens.map((token) => {
      const item = document.createElement("li");
      const expired = token.certificateValid === false;
      item.append(line("company", token.companyName || token.displayName || "Token", "token-company"));
      if (token.taxCode) item.append(line("tax", `MST ${token.taxCode}`));
      item.append(line("holder", `Máy giữ token: ${token.via || holder}`));
      item.append(line("access", token.accessExpiresAt ? `Quyền đến ${day(token.accessExpiresAt)}` : "Quyền không thời hạn"));
      if (expired) item.append(line("certificate", "Chứng thư đã hết hạn", "bad"));
      else if (token.certificateNotAfter) item.append(line("certificate", `Chứng thư đến ${day(token.certificateNotAfter)}`));
      return item;
    }),
  );
  $("tokens-empty").hidden = tokens.length > 0;
}

$("reload").addEventListener("click", () => reloadTokens(true));
function showEnabled(enabled) {
  $("enabled").checked = enabled;
  $("enabled-label").textContent = enabled ? "BẬT" : "TẮT";
  $("enabled").closest(".power").classList.toggle("on", enabled);
  $("enabled-hint").textContent = enabled
    ? "Lệnh ký của website đi tới máy ký của công ty"
    : "Website dùng plugin ký cài trên máy này";
}

$("enabled").addEventListener("change", (event) => {
  showEnabled(event.target.checked);
  chrome.storage.local.set({ enabled: event.target.checked });
  say("Đã thay đổi chức năng, site sẽ được F5 để có tác dụng");
});
$("options").addEventListener("click", () => chrome.runtime.openOptionsPage());
$("help").addEventListener("click", () => chrome.tabs.create({ url: chrome.runtime.getURL("help.html") }));
$("copy-id").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("device-id").textContent);
  say("Đã copy ID thiết bị");
});
$("primary").addEventListener("click", async () => {
  const { serverUrl } = await chrome.storage.local.get(["serverUrl"]);
  if (signedIn) {
    chrome.tabs.create({ url: `${serverUrl}/sign` });
    return;
  }
  say("Đang tìm máy chủ…");
  const found = serverUrl ? { url: serverUrl } : await send({ t: "discover" });
  if (!found.url) {
    say("Chưa có máy chủ: mở link kết nối quản trị viên gửi.");
    return;
  }
  say("Đang mở trang đăng nhập…");
  const result = await send({ t: "login", serverUrl: found.url });
  say(result.ok ? "" : result.error);
  render();
});
$("disconnect").addEventListener("click", async () => {
  if (!agent || !confirm(`Ngắt kết nối với ${agent.name || agent.agentId}? Muốn dùng lại phải mở link kết nối mới.`)) return;
  await send({ t: "remove_agent", agentId: agent.agentId });
  render();
});
// "Kết nối" first asks who is connecting; the admin approves people.
$("lan-connect").addEventListener("click", async () => {
  const { deviceName = "" } = await chrome.storage.local.get(["deviceName"]);
  $("lan-form").hidden = false;
  $("lan-name").value = deviceName;
  $("lan-name").focus();
});
$("lan-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const deviceName = $("lan-name").value.trim();
  if (deviceName.length < 2) return say("Hãy nhập tên của bạn");
  $("lan-form").hidden = true;
  say("Đang gửi yêu cầu…");
  const result = await send({ t: "lan_request", deviceName });
  const answers = {
    welcome: "Đã kết nối, máy này đã được cấp quyền.",
    pending: "Đã gửi yêu cầu. Chờ quản trị viên duyệt rồi mở lại tiện ích.",
    timeout: "Agent chưa trả lời, thử lại sau.",
  };
  say(result?.ok ? answers.welcome : answers[result?.state] || result?.error || "Không gửi được yêu cầu");
  render();
});
$("lan-google").addEventListener("click", async () => {
  say("Đang mở trang đăng nhập…");
  const result = await send({ t: "lan_login" });
  say(result?.ok ? `Đã đăng nhập: ${result.user?.displayName || result.user?.username || ""}` : result?.error || "Chưa đăng nhập được");
  render();
});
$("demo").addEventListener("click", async () => {
  const result = await send({ t: "demo_prompt" });
  if (result?.ok) window.close();
  else say(result?.error || "Không mở được hộp xác nhận");
});

render();
// Each time the popup opens: fresh token list (cached one shows first) and a
// quiet look for an agent on the office network.
reloadTokens();
send({ t: "lan_scan" }).then(render);
