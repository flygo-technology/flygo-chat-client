const $ = (id) => document.getElementById(id);
const send = (message) => chrome.runtime.sendMessage(message);

function label(status) {
  switch (status?.state) {
    case "connected":
      return "đã kết nối";
    case "connecting":
      return "đang kết nối…";
    default:
      return status?.error || "chưa kết nối";
  }
}

async function render() {
  const { serverUrl = "", token = "", displayName = "", username = "", agents = [] } = await chrome.storage.local.get([
    "serverUrl",
    "token",
    "displayName",
    "username",
    "agents",
  ]);
  const device = await send({ t: "device" });
  const status = await send({ t: "status" });
  // Relay mode: the agent grants access, there is nothing to log in to.
  const relay = agents.length > 0;
  $("signed-out").hidden = relay || !!token;
  $("signed-in").hidden = relay || !token;
  $("who").textContent = displayName || username;
  $("where").textContent = serverUrl;
  $("device-name").textContent = device.deviceName;
  if (!$("device").value) $("device").value = device.deviceName;
  $("server").textContent = serverUrl
    ? `Máy chủ: ${serverUrl}`
    : "Chưa có máy chủ. Mở link kết nối hoặc trang quản trị máy chủ ký để cài đặt.";
  $("login-button").disabled = !serverUrl;
  $("status").textContent = relay
    ? `Agent ${agents[0].name || agents[0].agentId}: ${label(status)}`
    : `Trạng thái: ${label(status)}`;
}

$("login").addEventListener("submit", async (event) => {
  event.preventDefault();
  const { serverUrl } = await chrome.storage.local.get(["serverUrl"]);
  if (!serverUrl) return;
  $("message").textContent = "Đang mở trang đăng nhập…";
  const result = await send({ t: "login", serverUrl, deviceName: $("device").value });
  $("message").textContent = result.ok ? "Đã đăng nhập." : `Lỗi: ${result.error}`;
  render();
});

$("logout").addEventListener("click", async () => {
  await send({ t: "logout" });
  $("message").textContent = "";
  render();
});

$("open").addEventListener("click", async () => {
  const { serverUrl } = await chrome.storage.local.get(["serverUrl"]);
  chrome.tabs.create({ url: `${serverUrl}/sign` });
});

render();
setInterval(render, 3000);
