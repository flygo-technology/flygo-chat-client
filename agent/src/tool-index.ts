// Tìm tool khi cần (Sếp 2026-11-25: "Flygo Chat cung cấp hơn 300 tool cho agent … agent chỉ tự tìm tool khi cần thiết").
// MCP flygo_chat chỉ đưa bộ LÕI + tool_search / tool_describe / tool_call; mọi tool khác (tool của bot, tool app công ty qua
// Gateway) nằm trong chỉ mục này. Tìm theo từ khoá (bỏ dấu tiếng Việt), tên app và từ đồng nghĩa Việt ↔ Anh.

export interface ToolDef { name: string; title?: string; description?: string; inputSchema?: any; annotations?: any }

/** Nhóm (app) của tool: tool Gateway "vn_flygo_<app>__x" → <app> (trình duyệt tách riêng); tool của bot → theo tiền tố. */
export function appOf(name: string): string {
  const g = /^vn_flygo_([a-z0-9_]+?)__(.+)$/.exec(name);
  if (g) {
    if (g[1] === "clients") return /^(integrated_)?browser_/.test(g[2]) ? (g[2].startsWith("integrated_") ? "ky-so" : "browser") : "clients";
    return g[1].replace(/^web_/, "").replace(/_/g, "-");
  }
  const m = /^vn_([a-z0-9]+)_([a-z0-9_]+?)__/.exec(name);
  if (m) return `${m[1]}-${m[2]}`.replace(/_/g, "-");
  if (/^(chat|ref)_/.test(name)) return "chat";
  if (/^(session|project|team|spawn)_/.test(name)) return "session";
  if (/^(agent|remote_agent|ask_agent)/.test(name)) return "agent";
  if (/^(file|run_command)/.test(name)) return "file";
  if (/^(skill|role)_/.test(name)) return "skill";
  if (/^schedule_/.test(name)) return "schedule";
  if (/^meeting_/.test(name)) return "meeting";
  if (/^adb_/.test(name)) return "phone";
  if (/^(browser_open_profiles|integrated_browser_open)$/.test(name)) return "browser";
  return "other";
}

/** Tên tiếng Việt của nhóm (liệt kê trong mô tả tool_search để agent biết có gì). */
export const APP_LABEL: Record<string, string> = {
  browser: "trình duyệt của Sếp (mở trang, bấm, gõ, chụp, đọc)", "ky-so": "trình duyệt Ký số (hải quan, thuế, ngân hàng)",
  meet: "Họp trực tuyến", mail: "Thư", calendar: "Lịch", "office": "Office (Word / Excel)", drive: "Drive / tệp công ty",
  flows: "Quy trình", forms: "Biểu mẫu", reports: "Báo cáo", todo: "Việc cần làm", wiki: "Wiki", teamwork: "Làm việc nhóm",
  bangtin: "Bảng tin", contacts: "Danh bạ", directory: "Tổ chức / phòng ban", ai: "Cổng AI", "bank-techcombank": "Ngân hàng Techcombank",
  teable: "Teable", multica: "Multica", chat: "chat (đọc / gửi / tìm tin, tệp)", session: "phiên AI, dự án, đồng đội", agent: "nhờ agent khác",
  file: "tệp & lệnh trên máy", skill: "kỹ năng", schedule: "lịch hẹn tự chạy", meeting: "dẫn cuộc họp", phone: "điện thoại Android",
};

const strip = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
const words = (s: string) => strip(s).split(/[^a-z0-9]+/).filter((w) => w.length > 1);

/** Từ đồng nghĩa (không dấu): từ của người dùng → từ có trong tên / mô tả tool. */
const SYN: Record<string, string[]> = {
  "trinh duyet": ["browser"], web: ["browser", "navigate"], trang: ["browser", "page", "navigate"], "mo trang": ["navigate"],
  bam: ["click"], click: ["click"], go: ["type"], dien: ["type", "fill"], "chup man hinh": ["screenshot"], chup: ["screenshot"],
  "ky so": ["integrated", "sign", "ky-so"], token: ["integrated", "sign"], "hai quan": ["integrated", "customs"], thue: ["integrated", "tax"],
  thu: ["mail", "email"], email: ["mail"], mail: ["mail"], nhap: ["draft"], "thu nhap": ["draft", "mail"], gui: ["send"],
  hop: ["meet", "meeting"], "cuoc hop": ["meet", "meeting"], lich: ["calendar", "event", "schedule"], "lich hen": ["schedule", "calendar"],
  viec: ["todo", "task"], "cong viec": ["todo", "task"], "bieu mau": ["forms", "form"], form: ["forms"], "bao cao": ["reports", "report"],
  "quy trinh": ["flows", "flow"], "ngan hang": ["bank", "techcombank"], "giao dich": ["transactions", "bank"], "so du": ["balance", "bank"],
  tep: ["file", "drive"], "tai lieu": ["drive", "office", "file", "wiki"], word: ["office", "docx"], excel: ["office", "xlsx", "sheet"],
  "danh ba": ["contacts"], "phong ban": ["directory", "department"], "nhan vien": ["directory", "users"], tin: ["chat", "message", "post"],
  "tin nhan": ["chat", "message"], nhom: ["chat", "channel", "group"], "tim": ["search", "find"], doc: ["read", "get"], tao: ["create", "new"],
  sua: ["update", "edit"], xoa: ["delete", "trash", "remove"], "dien thoai": ["adb", "phone"], "dang nhap": ["login", "secret"],
  "mat khau": ["secret", "password"], "han muc": ["ai", "quota"], ai: ["ai"], wiki: ["wiki"], "lenh": ["run_command", "command"],
  "ghi chu": ["note", "todo"], "viec can lam": ["todo", "checklist", "note"], nhac: ["reminder"], "su kien": ["event", "calendar"],
  "hop ngay": ["start_now", "meet"], "tao cuoc hop": ["schedule", "start_now"], "to chuc hop": ["schedule", "start_now"], "len lich": ["schedule"], moi: ["invite", "guests"], "cuoc goi": ["meet"],
};

export interface Hit { name: string; app: string; title: string; score: number }

export class ToolIndex {
  private items: { t: ToolDef; app: string; name: string; text: string; nameWords: Set<string> }[] = [];
  constructor(tools: ToolDef[]) {
    for (const t of tools) {
      const app = appOf(t.name);
      const nameWords = new Set(words(t.name.replace(/__/g, " ")));
      this.items.push({ t, app, name: t.name, nameWords, text: ` ${words(`${t.title ?? ""} ${t.description ?? ""}`).join(" ")} ` });
    }
  }
  get size() { return this.items.length; }
  get(name: string) { return this.items.find((x) => x.name === name)?.t; }
  /** Nhóm → số tool (để liệt kê trong mô tả). */
  apps(): Record<string, number> { const r: Record<string, number> = {}; for (const x of this.items) r[x.app] = (r[x.app] ?? 0) + 1; return r; }

  search(query: string, o: { app?: string; limit?: number } = {}): Hit[] {
    const q = strip(query);
    const terms = new Set(words(q));
    for (const [k, v] of Object.entries(SYN)) if (` ${q} `.includes(` ${k} `)) v.forEach((x) => terms.add(x));
    const appQ = o.app ? strip(o.app) : "";
    const hits: Hit[] = [];
    for (const x of this.items) {
      if (appQ && !x.app.includes(appQ) && !x.name.includes(appQ)) continue;
      let s = 0;
      for (const w of terms) {
        if (x.nameWords.has(w)) s += 3;
        else if ([...x.nameWords].some((n) => n.startsWith(w) || w.startsWith(n) && n.length > 3)) s += 2;
        if (x.app === w || x.app.split("-").includes(w)) s += 2;
        if (x.text.includes(` ${w} `)) s += 1;
      }
      if (s > 0) hits.push({ name: x.name, app: x.app, title: x.t.title || firstLine(x.t.description), score: s });
    }
    return hits.sort((a, b) => b.score - a.score || a.name.length - b.name.length).slice(0, o.limit ?? 8);
  }
}

export const firstLine = (s?: string) => (s ?? "").split(/\n|(?<=\.)\s/)[0].slice(0, 160);

/** Schema rút gọn để trả trong kết quả tìm (tên tham số, kiểu, bắt buộc), không kèm mô tả dài. */
export function compactSchema(s: any): any {
  const p = s?.properties ?? {};
  return { required: s?.required ?? [], params: Object.fromEntries(Object.entries<any>(p).map(([k, v]) => [k, v?.type ?? (v?.enum ? "enum" : "any")])) };
}

/** Bộ LÕI luôn có (khoảng 25 tool) — đủ cho việc thường ngày; còn lại tìm bằng tool_search. */
export const CORE_TOOLS = new Set([
  "chat_history", "chat_thread", "chat_search", "chat_info", "chat_files", "chat_read_file", "chat_send_files",
  "chat_send", "chat_reply", "chat_list", "agent_send", "agent_list", "ask_user", "approve", "update_plan", "wrap_up",
  "run_command", "file_read", "file_write", "skill_list", "skill_read", "session_list", "session_read", "chat_report_out",
  "artifact_publish", "schedule_create",
]);

/** tool_call cần xin duyệt ở đây không: tool tự xin duyệt bên trong (Gateway ghi, tệp / lệnh, chat_op, điện thoại) hoặc vốn được
 *  phép (FLYGO_ALLOWED_TOOLS = các tool flygo_chat engine cho chạy không hỏi; "*" = mọi tool) thì không; còn lại xin như engine xin. */
export function toolCallNeedsApproval(name: string, o: { gateway: boolean; selfApproving: boolean; allowed: string }): boolean {
  if (o.gateway || o.selfApproving) return false;
  if (o.allowed === "*") return false;
  return !o.allowed.split(",").map((x) => x.trim()).includes(name);
}
