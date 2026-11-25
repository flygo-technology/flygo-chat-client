import type { StepKind, StepStatus } from "../card";
import type { UsageLimits } from "../limits";
import type { Todo } from "../todos";

export interface ApprovalRequest {
  kind: "command" | "file" | "tool" | "report" | "plan";
  title: string; // một dòng: lệnh / file / tool
  detail?: string;
  tool?: string; // tên tool xin duyệt (vd. mcp__flygo_chat__vn_flygo_mail__mail_send)
}
export type ApprovalDecision = "accept" | "decline";
/** Chế độ quyền người dùng chọn trên app: Thủ công / Chấp nhận chỉnh sửa / Lập kế hoạch / Tự động. */
export type PermMode = "manual" | "acceptEdits" | "plan" | "auto" | "bypassPermissions";
export const PERM_MODES: PermMode[] = ["manual", "acceptEdits", "plan", "auto", "bypassPermissions"];

/** Câu hỏi agent hỏi người dùng (Claude AskUserQuestion, Codex request_user_input, tool MCP ask_user). */
export interface UserQuestion {
  id: string;
  question: string;
  header?: string;
  options: { label: string; description?: string }[];
  multi?: boolean;
}
/** Trả lời từng câu (cùng thứ tự); null = người dùng huỷ / hết hạn / không hỏi được. */
export interface UserAnswer { choices: string[]; other?: string }
export type AskResult = { answers: UserAnswer[] } | { cancelled: true; reason: string };
/** Câu trả lời dạng chữ cho agent: các lựa chọn + ý khác. */
export const answerText = (a: UserAnswer) => [...a.choices, ...(a.other ? [a.other] : [])].join(", ");

export interface TurnHooks {
  step(s: { id: string; kind: StepKind; title: string; label?: string; status: StepStatus; detail?: string }): void;
  /** Tin nhắn của agent đang stream: `delta` nối thêm, hoặc `full` thay toàn bộ; `done` khi tin đã xong. */
  text(m: { id: string; delta?: string; full?: string; done?: boolean }): void;
  approval(req: ApprovalRequest): Promise<ApprovalDecision>;
  /** Hỏi người dùng (trả lời ngay trong lượt). */
  ask(questions: UserQuestion[]): Promise<AskResult>;
  session(id: string): void; // engine báo session/thread id ngay khi có
  /** Danh sách việc agent tự lập (TodoWrite / plan): bản mới nhất thay bản cũ. */
  todos?(list: Todo[]): void;
  /** Engine cho phép đưa tin mới vào lượt đang chạy (Codex turn/steer): fn khi lượt bắt đầu, null khi lượt kết thúc.
   *  fn trả true = đã nhận vào hàng chờ của lượt; onRead gọi khi agent thật sự đọc tin (Claude: lúc phát lại tin user,
   *  Codex: ngay khi turn/steer xong) -> runner đổi nhãn "Đã điều hướng". */
  steerable?(fn: ((text: string, onRead?: () => void) => Promise<boolean>) | null): void;
  /** Một lần gọi tool đã xong (có input + kết quả): runner nhận diện tác vụ nền (bg-tasks.ts). */
  toolDone?(t: { id: string; name: string; input: any; result: string; isError: boolean }): void;
}

export interface TurnInput {
  sessionId?: string; // trống = phiên mới
  forkFrom?: string; // phiên mới tách (fork) từ phiên này (phiên cha: chat chính / nhóm cha), mang theo ngữ cảnh của nó
  cwd: string;
  prompt: string;
  persona: string; // hướng dẫn hệ thống (xưng hô, quy tắc)
  title: string; // tên phiên hiện trên Codex app / claude --resume: "<tên chat> · <tên luồng | Luồng chính>"
  group: string; // nhóm phiên theo chat (Codex: section "Flygo · <tên chat>")
  mcpEnv: Record<string, string>; // env cho MCP server flygo_chat của phiên này
  model?: string; // model cho lượt này (người dùng chọn hoặc mặc định)
  effort?: string; // mức suy nghĩ cho lượt này
  fallbackModel?: string; // model mặc định của bot: model đã chọn bị upstream từ chối thì chạy lại bằng model này (Codex)
  addDirs?: string[]; // thư mục thêm (Claude: --add-dir; Antigravity: kỹ năng riêng của bot)
  pluginDirs?: string[]; // Claude: --plugin-dir (kỹ năng riêng của bot, nạp được cả khi --setting-sources "")
  bypass?: boolean; // chủ bot "luôn cho phép" phạm vi này: không hỏi duyệt, toàn quyền
  twBypass?: boolean; // lượt TeamWork không cần duyệt (token hợp lệ + chủ bot + công tắc bật): không hỏi duyệt nhưng GIỮ danh sách cấm
  extMcp?: Record<string, { url: string; headers: Record<string, string> }>; // MCP bên ngoài (Streamable HTTP) của chủ bot đang bật
  research?: boolean; // Nghiên cứu sâu: Codex bật tìm web trực tiếp (web_search = "live")
  mode?: PermMode; // chế độ quyền của lượt (thiếu = mặc định của engine: Claude thủ công, Codex chấp nhận chỉnh sửa)
  readOnly?: boolean; // hỏi ngầm (team_ask / session_ask): sandbox chỉ đọc, không xin duyệt, mọi thay đổi bị chặn (Codex)
  requester?: string; // id Mattermost của người nhờ lượt này (Cổng AI tính hạn mức theo người này; thiếu = chủ bot)
}

export interface TurnResult {
  sessionId: string;
  text: string; // câu trả lời cuối
  usage?: Record<string, any>;
}

/** Kiểm kê của engine trên máy: kỹ năng engine tự nạp, model dùng được. */
export interface EngineInventory {
  skills: { name: string; description: string }[];
  models: { id: string; name?: string; efforts: string[]; defaultEffort?: string; isDefault?: boolean }[];
  /** Bí danh model -> id đầy đủ (Claude: opus -> claude-opus-5-5, fable -> claude-fable-5-2…). */
  aliases?: Record<string, string>;
}

export interface Engine {
  name: "codex" | "claude" | "agy";
  inventory(): Promise<EngineInventory>;
  runTurn(input: TurnInput, hooks: TurnHooks, signal: AbortSignal): Promise<TurnResult>;
  /** Cỡ ngữ cảnh hiện tại của phiên (token của lần gọi model gần nhất); null = không đọc được (không có phiên trên máy). */
  contextTokens(sessionId: string): Promise<number | null>;
  /** Hạn mức sử dụng của tài khoản engine (cửa sổ 5 giờ / tuần…); null = không biết. */
  usageLimits?(): Promise<UsageLimits | null>;
  /** Dừng bot (runner chung): đóng kết nối / tiến trình engine riêng của bot. */
  dispose?(): void;
}
