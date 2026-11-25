// Sub-agent đang chạy (Sếp 2026-11-25: "cần bổ sung liệt kê sub agent đang chạy nữa (tương tự sub-process đang có)").
// Nguồn: stream-json của Claude Code — tool_use Task/Agent mở một sub-agent; sự kiện system task_started / task_progress /
// task_notification và tin có parent_tool_use_id cho tiến độ; tool_result (hoặc task_notification với sub-agent chạy nền) kết thúc.
// Thẻ: props.flygo_agent.subagents (hợp đồng với app "agent chat ui", feat/agent-traffic-cards).
import { redact } from "./bg-tasks";

export type SubStatus = "running" | "done" | "failed" | "stopped";
export interface Subagent {
  id: string; // tool_use_id của Task / Agent
  task_id?: string; // id task của Claude Code (để dừng: control stop_task)
  type: string;
  title: string;
  prompt: string;
  model?: string;
  background: boolean;
  status: SubStatus;
  started_at: number;
  ended_at?: number;
  updated_at: number;
  last_action?: string;
  tool_uses: number;
  tokens?: { input?: number; output?: number; total?: number };
  result?: string;
  error?: string;
}

const MAX = 4096;
const cut = (s: string, n = MAX) => (s.length > n ? `${s.slice(0, n)}…` : s);
const isSubTool = (name: string) => name === "Task" || name === "Agent";

/** Mô tả ngắn một tool sub-agent vừa gọi (last_action). */
export function actionOf(name: string, input: any): string {
  const s = (v: any) => String(v ?? "").replace(/\s+/g, " ").trim();
  switch (name) {
    case "Bash": return `Đã chạy: ${cut(redact(s(input?.command)), 100)}`;
    case "Read": return `Đọc ${s(input?.file_path).split("/").slice(-3).join("/")}`;
    case "Edit": case "MultiEdit": case "Write": return `Sửa ${s(input?.file_path).split("/").slice(-3).join("/")}`;
    case "Grep": case "Glob": return `Tìm ${cut(s(input?.pattern), 80)}`;
    case "WebSearch": return `Tìm web: ${cut(s(input?.query), 80)}`;
    case "WebFetch": return `Mở ${cut(s(input?.url), 80)}`;
    default: return cut(name.replace(/^mcp__([^_]+(?:_[^_]+)*)__/, "$1."), 80);
  }
}

export class SubagentTracker {
  list: Subagent[] = [];
  private byTask = new Map<string, Subagent>();
  constructor(private onChange: () => void, private now = () => Date.now()) {}

  get active() { return this.list.some((s) => s.status === "running"); }
  get(id: string) { return this.list.find((s) => s.id === id); }

  private touch(s: Subagent) { s.updated_at = this.now(); this.onChange(); }
  private end(s: Subagent, status: SubStatus, o: { result?: string; error?: string } = {}) {
    if (s.status !== "running") return;
    s.status = status; s.ended_at = this.now();
    if (o.result) s.result = cut(redact(o.result));
    if (o.error) s.error = cut(redact(o.error), 500);
    this.touch(s);
  }

  /** Một sự kiện stream-json của claude (mọi loại; chỉ lấy phần liên quan sub-agent). */
  onEvent(ev: any) {
    if (ev?.type === "system") return this.onSystem(ev);
    const parent: string | undefined = ev?.parent_tool_use_id ?? undefined;
    const content = ev?.message?.content;
    if (!Array.isArray(content)) return;
    if (ev.type === "assistant") {
      for (const c of content) {
        if (c?.type !== "tool_use") continue;
        if (!parent && isSubTool(c.name)) {
          const i = c.input ?? {};
          const t0 = this.now();
          this.list.push({ id: c.id, type: String(i.subagent_type ?? "general-purpose"), title: cut(String(i.description ?? "Sub-agent"), 80), prompt: cut(redact(String(i.prompt ?? ""))),
            ...(i.model ? { model: String(i.model) } : {}), background: !!i.run_in_background, status: "running", started_at: t0, updated_at: t0, tool_uses: 0 });
          this.onChange();
        } else if (parent) {
          const s = this.get(parent);
          if (s && s.status === "running") { s.tool_uses++; s.last_action = actionOf(c.name, c.input); this.touch(s); }
        }
      }
    } else if (ev.type === "user" && !parent) {
      for (const c of content) {
        if (c?.type !== "tool_result") continue;
        const s = this.get(c.tool_use_id);
        if (!s) continue;
        const text = typeof c.content === "string" ? c.content : Array.isArray(c.content) ? c.content.map((x: any) => x?.text ?? "").join("\n") : "";
        if (c.is_error) this.end(s, "failed", { error: text });
        else if (s.background) { s.result = cut(redact(text), 600); this.touch(s); } // chạy nền: kết quả thật tới sau (task_notification)
        else this.end(s, "done", { result: text });
      }
    }
  }

  private onSystem(ev: any) {
    const s = (ev.tool_use_id && this.get(ev.tool_use_id)) || (ev.task_id && this.byTask.get(ev.task_id));
    if (!s) return;
    if (ev.task_id && !s.task_id) { s.task_id = String(ev.task_id); this.byTask.set(s.task_id, s); }
    if (ev.subtype === "task_started") {
      if (ev.is_backgrounded) s.background = true;
      this.touch(s);
    } else if (ev.subtype === "task_progress") {
      const u = ev.usage ?? {};
      if (Number.isFinite(u.tool_uses)) s.tool_uses = u.tool_uses;
      if (Number.isFinite(u.total_tokens)) s.tokens = { ...(s.tokens ?? {}), total: u.total_tokens };
      if (ev.last_tool_name && !s.last_action) s.last_action = String(ev.last_tool_name);
      if (ev.summary) s.last_action = cut(String(ev.summary), 120);
      this.touch(s);
    } else if (ev.subtype === "task_notification") {
      const u = ev.usage ?? {};
      if (u.input_tokens || u.output_tokens || u.total_tokens) s.tokens = { input: u.input_tokens, output: u.output_tokens, total: u.total_tokens };
      const st = String(ev.status ?? "");
      this.end(s, st === "completed" ? "done" : st === "failed" ? "failed" : st === "killed" || st === "stopped" ? "stopped" : "done",
        st === "failed" ? { error: String(ev.reason ?? ev.summary ?? "") } : { result: String(ev.summary ?? s.result ?? "") });
    }
  }

  /** Hết lượt: tiến trình claude thoát (không giữ phiên sống) thì sub-agent còn chạy dừng theo. */
  endTurn(claudeAlive: boolean) {
    if (claudeAlive) return;
    for (const s of this.list) if (s.status === "running") this.end(s, "stopped", { error: "dừng cùng lượt" });
  }

  markStopped(id: string) { const s = this.get(id); if (s) this.end(s, "stopped", { error: "Sếp dừng" }); }
}
