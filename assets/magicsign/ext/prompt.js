// Confirmation dialog shown on the website that asked for a signature.
// Runs in the isolated world of the top frame. The dialog lives in a closed
// shadow root and only accepts trusted (real user) clicks, so page scripts
// cannot read it or press its buttons.
(() => {
  "use strict";
  if (window.__magicSignPrompt) return;
  window.__magicSignPrompt = true;

  const queue = [];
  let current = null; // { prompt, selected, acknowledged, state, message }
  let host = null;
  let root = null;

  const STYLE = `
    :host { all: initial; }
    .overlay {
      position: fixed; inset: 0; z-index: 2147483647;
      display: grid; place-items: center; padding: 16px;
      background: rgba(15, 23, 42, 0.55);
      font: 14px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      color: #101828;
    }
    .card {
      width: min(560px, 100%); max-height: calc(100vh - 32px); overflow: auto;
      background: #fff; border-radius: 12px; box-shadow: 0 24px 48px rgba(0,0,0,.25);
      display: grid; gap: 14px; padding: 20px;
    }
    @media (prefers-color-scheme: dark) {
      .overlay { color: #e4e7ec; }
      .card { background: #1d2433; }
      .cert { border-color: #344054 !important; }
      .muted { color: #98a2b3 !important; }
      .site, .tech { background: #283044 !important; }
    }
    h2 { margin: 0; font-size: 18px; }
    .muted { color: #667085; font-size: 12.5px; }
    .site { background: #f2f4f7; border-radius: 8px; padding: 10px 12px; display: grid; gap: 2px; }
    .site strong { font-size: 15px; word-break: break-all; }
    .url { word-break: break-all; }
    .alert { border-radius: 8px; padding: 10px 12px; font-size: 13px; }
    .alert.warning { background: #fffaeb; color: #93370d; border: 1px solid #fedf89; }
    .alert.danger { background: #fef3f2; color: #b42318; border: 1px solid #fecdca; }
    .alert.info { background: #f2f4f7; color: #475467; }
    .certs { display: grid; gap: 8px; }
    .cert {
      display: grid; grid-template-columns: auto 1fr; gap: 4px 10px; align-items: start;
      border: 1.5px solid #d0d5dd; border-radius: 10px; padding: 10px 12px; cursor: pointer;
    }
    .cert.selected { border-color: #2557d6; box-shadow: 0 0 0 3px rgba(37, 87, 214, .15); }
    .cert input { margin: 3px 0 0; }
    .company { font-weight: 600; }
    .tax { font-weight: 600; }
    .badges { display: flex; flex-wrap: wrap; gap: 6px; grid-column: 2; }
    .badge { font-size: 11.5px; border-radius: 999px; padding: 1px 8px; background: #f2f4f7; color: #344054; }
    .badge.ok { background: #ecfdf3; color: #067647; }
    .badge.bad { background: #fef3f2; color: #b42318; }
    .tech { background: #f9fafb; border-radius: 8px; padding: 8px 10px; font: 12px ui-monospace, monospace; word-break: break-all; }
    details summary { cursor: pointer; }
    .ack { display: flex; gap: 8px; align-items: flex-start; font-size: 13px; }
    .actions { display: flex; justify-content: flex-end; gap: 8px; }
    button {
      font: inherit; border-radius: 8px; padding: 8px 16px; cursor: pointer;
      border: 1px solid #d0d5dd; background: transparent; color: inherit;
    }
    button.primary { background: #2557d6; border-color: #2557d6; color: #fff; font-weight: 600; }
    button:disabled { opacity: .45; cursor: not-allowed; }
    .spinner {
      width: 18px; height: 18px; border-radius: 50%; border: 2px solid #d0d5dd;
      border-top-color: #2557d6; animation: spin 1s linear infinite;
    }
    .waiting { display: flex; gap: 10px; align-items: center; }
    @keyframes spin { to { transform: rotate(360deg); } }
  `;

  function el(tag, attributes = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attributes)) {
      if (value === undefined || value === null || value === false) continue;
      if (key === "class") node.className = value;
      else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
      else node.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat(Infinity)) {
      if (child === null || child === undefined || child === false) continue;
      node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  /** Accept only clicks made by the user, never page-dispatched events. */
  const trusted = (handler) => (event) => {
    if (!event.isTrusted) return;
    handler(event);
  };

  function formatDate(value) {
    if (!value) return "không rõ";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString("vi-VN");
  }

  function mount() {
    if (host?.isConnected) return;
    host = document.createElement("magic-sign-confirm");
    root = host.attachShadow({ mode: "closed" });
    (document.body || document.documentElement).append(host);
  }

  function unmount() {
    host?.remove();
    host = null;
    root = null;
  }

  async function answer(approved, remember = false) {
    if (!current || current.state !== "open") return;
    // The apps confirm with the device's own check first (biometrics,
    // password or the app's PIN); "Ký và nhớ 60 giây" skips it for a minute.
    if (approved && typeof window.__msConfirm === "function") {
      const asked = current;
      asked.state = "checking";
      asked.message = "Xác thực bằng vân tay / khuôn mặt…";
      render();
      const result = await window.__msConfirm({ remember }).catch((error) => ({ ok: false, error: String(error) }));
      if (current !== asked) return;
      if (!result?.ok) {
        asked.state = "open";
        asked.message = result?.error || "Chưa xác thực được, chưa ký.";
        render();
        return;
      }
      asked.state = "open";
      asked.message = "";
    }
    const tokenId = approved ? current.selected : null;
    chrome.runtime.sendMessage({ t: "prompt_reply", pid: current.prompt.pid, approved, tokenId });
    current.state = "sent";
    current.message = approved ? "Đã xác nhận, đang ký…" : "Đã từ chối.";
    render();
  }

  function next() {
    current = null;
    const prompt = queue.shift();
    if (!prompt) return unmount();
    const certificates = prompt.certificates || [];
    // Preselect only when there is nothing to choose.
    const only = certificates.length === 1 && certificates[0].matchesRequest !== false ? certificates[0].tokenId : null;
    current = { prompt, selected: only, acknowledged: false, state: "open", message: "" };
    render();
    // Within the minute after "Ký và nhớ 60 giây": confirm by itself when
    // nothing needs a choice or a warning acknowledged.
    const asked = current;
    const warned = (prompt.warnings || []).some((item) => item.level === "danger");
    if (only && !warned && typeof window.__msRemembered === "function") {
      window.__msRemembered().then((remembered) => remembered && current === asked && answer(true), () => {});
    }
  }

  function render() {
    if (!current) return;
    mount();
    const { prompt } = current;
    const certificates = prompt.certificates || [];
    const chosen = certificates.find((certificate) => certificate.tokenId === current.selected);
    const mismatch = chosen?.matchesRequest === false || (prompt.warnings || []).some((item) => item.level === "danger");
    const canConfirm = current.state === "open" && !!chosen && (!mismatch || current.acknowledged);

    const body =
      current.state === "open"
        ? [
            current.message && el("div", { class: "alert danger" }, current.message),
            prompt.requested && el("div", { class: "muted" }, `Website yêu cầu chứng thư: ${prompt.requested}`),
            (prompt.warnings || []).map((item) => el("div", { class: `alert ${item.level}` }, item.text)),
            el("div", {}, el("strong", {}, "Chọn chứng thư để ký")),
            el(
              "div",
              { class: "certs", role: "radiogroup" },
              certificates.map((certificate) =>
                el(
                  "label",
                  {
                    class: certificate.tokenId === current.selected ? "cert selected" : "cert",
                    onclick: trusted((event) => {
                      event.preventDefault();
                      current.selected = certificate.tokenId;
                      current.acknowledged = false;
                      render();
                    }),
                  },
                  el("input", { type: "radio", name: "certificate", checked: certificate.tokenId === current.selected }),
                  el(
                    "div",
                    {},
                    el("div", { class: "company" }, certificate.company || certificate.subject),
                    el("div", {}, "Mã số thuế: ", el("span", { class: "tax" }, certificate.taxCode || "không có trong chứng thư")),
                    el("div", { class: "muted" }, `Serial ${certificate.serial} · ${certificate.provider} · hạn đến ${formatDate(certificate.notAfter)}`),
                  ),
                  el(
                    "div",
                    { class: "badges" },
                    certificate.matchesRequest === true && el("span", { class: "badge ok" }, "Khớp yêu cầu của website"),
                    certificate.matchesRequest === false && el("span", { class: "badge bad" }, "Không khớp yêu cầu của website"),
                    certificate.needsApprover && el("span", { class: "badge" }, "Cần người duyệt ký"),
                  ),
                ),
              ),
            ),
            mismatch &&
              chosen &&
              el(
                "label",
                {
                  class: "ack",
                  onclick: trusted((event) => {
                    event.preventDefault();
                    current.acknowledged = !current.acknowledged;
                    render();
                  }),
                },
                el("input", { type: "checkbox", checked: current.acknowledged }),
                "Tôi đã kiểm tra và vẫn muốn ký bằng chứng thư này.",
              ),
            el(
              "div",
              { class: "actions" },
              el("button", { onclick: trusted(() => answer(false)) }, "Từ chối"),
              typeof window.__msRemembered === "function" &&
                el(
                  "button",
                  { disabled: !canConfirm, title: "Xác thực một lần, 60 giây sau đó ký không hỏi lại", onclick: trusted(() => canConfirm && answer(true, true)) },
                  "Ký và nhớ 60 giây",
                ),
              el(
                "button",
                { class: "primary", disabled: !canConfirm, onclick: trusted(() => canConfirm && answer(true)) },
                prompt.requirePin ? "Xác nhận ký" : "Xác nhận chọn",
              ),
            ),
          ]
        : [
            el("div", { class: "waiting" }, current.state !== "closed" && el("div", { class: "spinner" }), current.message),
            el("div", { class: "actions" }, el("button", { onclick: trusted(() => next()) }, "Ẩn")),
          ];

    const card = el(
      "div",
      { class: "card", role: "dialog", "aria-modal": "true", "aria-label": "Xác nhận ký số" },
      el("h2", {}, prompt.requirePin ? "Xác nhận ký số" : "Chọn chứng thư số"),
      el(
        "div",
        { class: "site" },
        el("span", { class: "muted" }, "Website yêu cầu"),
        el("strong", {}, prompt.origin),
        prompt.pageUrl && el("span", { class: "muted url" }, prompt.pageUrl),
      ),
      el(
        "div",
        {},
        el("div", {}, el("strong", {}, prompt.title)),
        prompt.description && el("div", {}, prompt.description),
        prompt.action && el("div", { class: "muted" }, `Thao tác: ${prompt.action}`),
      ),
      prompt.digest &&
        el("details", {}, el("summary", { class: "muted" }, "Thông tin kỹ thuật"), el("div", { class: "tech" }, `SHA-256: ${prompt.digest}`)),
      body,
    );

    root.replaceChildren(el("style", {}, STYLE), el("div", { class: "overlay" }, card));
  }

  chrome.runtime.onMessage.addListener((message) => {
    switch (message?.t) {
      case "magic-sign:prompt":
        queue.push(message.prompt);
        if (!current) next();
        break;
      case "magic-sign:prompt_state":
        if (current?.prompt.pid === message.pid) {
          current.state = "waiting";
          current.message = message.message || "Đang chờ xử lý…";
          render();
        }
        break;
      case "magic-sign:prompt_close": {
        const index = queue.findIndex((prompt) => prompt.pid === message.pid);
        if (index >= 0) queue.splice(index, 1);
        if (current?.prompt.pid === message.pid) next();
        break;
      }
    }
  });
})();
