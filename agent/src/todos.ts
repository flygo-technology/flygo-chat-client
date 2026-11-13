// Danh sách việc agent tự lập trong lượt (Claude TodoWrite, Codex turn/plan/updated, agy todo_write / update_plan),
// đưa về một dạng chung để app hiện như checklist trên thẻ tiến trình (props.flygo_agent.todos).
export type TodoStatus = "pending" | "in_progress" | "completed";
export interface Todo { text: string; status: TodoStatus }

const MAX_TODOS = 50;
const MAX_TEXT = 300;
const STATUS: Record<string, TodoStatus> = {
  pending: "pending", todo: "pending", not_started: "pending", notstarted: "pending", open: "pending", waiting: "pending",
  in_progress: "in_progress", inprogress: "in_progress", active: "in_progress", running: "in_progress", doing: "in_progress", started: "in_progress",
  completed: "completed", complete: "completed", done: "completed", finished: "completed", success: "completed",
};

/** Chuẩn hoá danh sách việc từ input của tool / thông báo của engine. Không nhận ra dạng danh sách thì trả null. */
export function normTodos(raw: any): Todo[] | null {
  let v = raw;
  if (typeof v === "string") { try { v = JSON.parse(v); } catch { return null; } }
  const list = Array.isArray(v) ? v : v?.todos ?? v?.plan ?? v?.items ?? v?.tasks ?? v?.steps;
  if (!Array.isArray(list)) return null;
  const out: Todo[] = [];
  for (const it of list) {
    const text = String(typeof it === "string" ? it : it?.content ?? it?.step ?? it?.text ?? it?.title ?? it?.task ?? it?.description ?? "").replace(/\s+/g, " ").trim();
    if (!text) continue;
    const key = String(typeof it === "string" ? "" : it?.status ?? it?.state ?? "").toLowerCase().replace(/[\s-]+/g, "_");
    out.push({ text: text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) + "…" : text, status: STATUS[key] ?? "pending" });
    if (out.length >= MAX_TODOS) break;
  }
  return out;
}
