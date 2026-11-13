// Lịch sử tin nhắn và bản ghi (transcript) phiên AI (0.6.73): phần thuần (không gọi máy chủ) để kiểm thử được.
//   - collectRange: phân trang ngược (before=<id tin cũ nhất>) tới khi qua mốc `from`, gộp + bỏ trùng + sắp cũ → mới, có trần.
//   - normPost / renderExportMd / renderExportJsonl: xuất lịch sử chat (tin, trả lời trong luồng, tệp, cảm xúc, sửa).
//   - parseClaudeJsonl / parseCodexRollout / parseAgyDb: đọc bản ghi của engine (Claude Code jsonl, Codex rollout, Antigravity .db).
//   - renderChatTranscript: kênh phiên AI trên Flygo Chat thành bản ghi (lượt người dùng / trợ lý, thẻ bước tóm tắt).
//   - redact: che token / khoá / mật khẩu trước khi trả cho model.
import { Database } from "bun:sqlite";
import { copyFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const TZ = "Asia/Ho_Chi_Minh";
export const fmtTime = (ms: number) => new Date(ms).toLocaleString("vi-VN", { timeZone: TZ, hour12: false });
/** yyyy-mm-dd theo giờ Việt Nam. */
export const dayOf = (ms: number) => new Date(ms + 7 * 3600_000).toISOString().slice(0, 10);
const hhmm = (ms: number) => new Date(ms + 7 * 3600_000).toISOString().slice(11, 19);
const clipTo = (s: string, n: number) => (s.length > n ? `${s.slice(0, n)}… (+${s.length - n} ký tự)` : s);

// ---------------------------------------------------------------- che bí mật
const MASK = "[đã ẩn]";
const SECRET_RES: [RegExp, string | ((...m: string[]) => string)][] = [
  [/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z0-9 ]*PRIVATE KEY-----|$)/g, `-----PRIVATE KEY ${MASK}-----`],
  [/\b(sk-(?:ant-|proj-|svcacct-)?[A-Za-z0-9_-]{20,})/g, MASK],
  [/\b[sr]k_(?:live|test)_[A-Za-z0-9]{10,}/g, MASK],
  [/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}/g, MASK],
  [/\bglpat-[A-Za-z0-9_-]{20,}/g, MASK],
  [/\bxox[abposr]-[A-Za-z0-9-]{10,}/g, MASK],
  [/\bAKIA[0-9A-Z]{16}\b/g, MASK],
  [/\bAIza[0-9A-Za-z_-]{35}\b/g, MASK],
  [/\bya29\.[0-9A-Za-z_-]{20,}/g, MASK],
  [/\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b/g, MASK], // token bot Telegram
  [/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, MASK], // JWT
  [/\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/-]{16,}=*/g, (_m, k) => `${k} ${MASK}`],
  [/(:\/\/[^\s:/@"']+):[^\s@/"']+@/g, (_m, u) => `${u}:${MASK}@`], // mật khẩu trong URL
  // khoá = giá trị (env, JSON, YAML, tham số dòng lệnh): giữ tên khoá, che giá trị.
  [/(\b[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret|auth[_-]?key|session[_-]?key|cookie)\b["']?\s*[=:]\s*["']?)([^\s"',;}{)]{6,})/gi,
    (_m, k, v) => (/^(true|false|null|undefined|none|\d{1,5})$/i.test(v) || v.startsWith("$") || v.startsWith("[đã") ? `${k}${v}` : `${k}${MASK}`)],
  [/(--(?:password|passwd|token|api-key|apikey|secret|client-secret|auth-token)[= ]+["']?)([^\s"']{6,})/gi, (_m, k) => `${k}${MASK}`],
];
/** Che token / khoá / mật khẩu thường gặp. */
export function redact(s: string): string {
  let out = String(s ?? "");
  for (const [re, rep] of SECRET_RES) out = out.replace(re, rep as any);
  return out;
}

// ---------------------------------------------------------------- khoảng thời gian
/** from / to đã phân tích (ms). Ngày trơn "2026-11-03" ở `to` = hết ngày đó. */
export function rangeOf(from: any, to: any, parseWhen: (v: any, dir: 1 | -1) => number | null): { from: number; to: number; err?: string } {
  const f = from === undefined || from === null || from === "" ? 0 : parseWhen(from, -1);
  let t = to === undefined || to === null || to === "" ? Infinity : parseWhen(to, -1);
  if (f === null) return { from: 0, to: Infinity, err: `from "${from}" không hợp lệ (vd. 2026-11-01, 2026-11-01T08:00, "7d", số ms)` };
  if (t === null) return { from: 0, to: Infinity, err: `to "${to}" không hợp lệ` };
  if (typeof to === "string" && /^\d{4}-\d\d-\d\d$/.test(to.trim())) t += 86400_000 - 1;
  if (f > t) return { from: f, to: t, err: "from sau to" };
  return { from: f, to: t };
}

// ---------------------------------------------------------------- phân trang
export interface Page<P> { posts: P[]; more: boolean }
export interface RangeResult<P> {
  posts: P[]; // trong khoảng, cũ → mới, không trùng
  scanned: number; // số tin đã đọc từ máy chủ
  pages: number;
  complete: boolean; // đã đọc hết khoảng (tới from hoặc đầu chat)
  reason?: "max_posts" | "max_scan" | "enough";
}
/**
 * Đọc ngược từ mới nhất: fetch(before) trả một trang (thứ tự bất kỳ), more=false khi hết. Dừng khi tin cũ nhất của trang
 * cũ hơn `from`, hết tin, đủ `maxPosts` tin trong khoảng, quét quá `maxScan` tin, hoặc `stopAt` tin (chỉ cần N tin mới nhất).
 */
export async function collectRange<P extends { id: string }>(
  fetch: (before?: string) => Promise<Page<P>>,
  o: { from: number; to: number; at: (p: P) => number; maxPosts: number; maxScan: number; stopAt?: number; keep?: (p: P) => boolean; onPage?: (scanned: number, kept: number) => void },
): Promise<RangeResult<P>> {
  const seen = new Map<string, P>();
  const ids = new Set<string>();
  let before: string | undefined, scanned = 0, pages = 0;
  for (;;) {
    const page = await fetch(before);
    pages++;
    const fresh = page.posts.filter((p) => !ids.has(p.id));
    if (!fresh.length) return done(true);
    for (const p of fresh) ids.add(p.id);
    scanned += fresh.length;
    let oldest = fresh[0];
    for (const p of fresh) {
      if (o.at(p) < o.at(oldest)) oldest = p;
      const t = o.at(p);
      if (t >= o.from && t <= o.to && (!o.keep || o.keep(p))) seen.set(p.id, p);
    }
    o.onPage?.(scanned, seen.size);
    if (o.at(oldest) < o.from || !page.more) return done(true);
    if (seen.size >= o.maxPosts) return done(false, "max_posts");
    if (o.stopAt && seen.size >= o.stopAt) return done(false, "enough");
    if (scanned >= o.maxScan) return done(false, "max_scan");
    before = oldest.id;
  }
  function done(complete: boolean, reason?: RangeResult<P>["reason"]): RangeResult<P> {
    let posts = [...seen.values()].sort((a, b) => o.at(a) - o.at(b) || (a.id < b.id ? -1 : 1));
    if (posts.length > o.maxPosts) { posts = posts.slice(-o.maxPosts); complete = false; reason = "max_posts"; }
    return { posts, scanned, pages, complete, reason };
  }
}

// ---------------------------------------------------------------- tin đã chuẩn hoá
export interface NFile { id: string; name: string; size?: number; mime?: string }
export interface NPost {
  id: string; at: number; user_id: string; user: string; root_id: string; message: string;
  edit_at?: number; reply_count?: number; pinned?: boolean; priority?: string;
  files: NFile[]; reactions: { emoji: string; users: string[] }[]; poll?: string; bot_card?: boolean;
}
/** Tin của máy chủ chat (Post + metadata) -> NPost. names: user_id -> tên hiển thị. */
export function normPost(p: any, names: Map<string, string>): NPost {
  const md = p.metadata ?? {};
  const rx = new Map<string, string[]>();
  for (const r of md.reactions ?? []) rx.set(r.emoji_name, [...(rx.get(r.emoji_name) ?? []), names.get(r.user_id) ?? r.user_id]);
  const files: NFile[] = (md.files ?? []).map((f: any) => ({ id: f.id, name: f.name, size: f.size, mime: f.mime_type }));
  if (!files.length && Array.isArray(p.file_ids)) for (const id of p.file_ids) files.push({ id, name: "(tệp)" });
  return {
    id: p.id, at: p.create_at, user_id: p.user_id, user: p.props?.override_username || names.get(p.user_id) || p.user_id, root_id: p.root_id || "",
    message: String(p.message ?? ""), edit_at: p.edit_at || undefined, reply_count: p.reply_count || undefined, pinned: !!p.is_pinned || undefined,
    priority: md.priority?.priority || undefined, files, reactions: [...rx].map(([emoji, users]) => ({ emoji, users })),
    poll: p.props?.flygo_poll ? `${p.props.flygo_poll.question ?? ""}: ${(p.props.flygo_poll.options ?? []).map((x: any) => x.text).join(" / ")}` : undefined,
  };
}
/** Tin từ relay /ref/read ({id, user, at ISO, message, root_id, file_list}) -> NPost. */
export function normRefPost(p: any): NPost {
  return {
    id: p.id, at: typeof p.at === "number" ? p.at : Date.parse(p.at) || 0, user_id: "", user: String(p.user ?? "?"), root_id: p.root_id || "", message: String(p.message ?? ""),
    files: (p.file_list ?? (p.files ?? []).map((name: string) => ({ id: "", name }))).map((f: any) => ({ id: f.id ?? "", name: f.name, size: f.size, mime: f.mime })),
    reactions: [],
  };
}

export type ThreadMode = "inline" | "nested" | "none";
/** Thứ tự xuất: inline = theo thời gian; nested = trả lời gom ngay dưới tin gốc; none = chỉ tin ở chat chính. */
export function orderPosts(posts: NPost[], mode: ThreadMode): { p: NPost; depth: number; orphanRoot?: string }[] {
  if (mode === "none") return posts.filter((p) => !p.root_id).map((p) => ({ p, depth: 0 }));
  if (mode === "inline") return posts.map((p) => ({ p, depth: 0 }));
  const byRoot = new Map<string, NPost[]>();
  const ids = new Set(posts.map((p) => p.id));
  for (const p of posts) if (p.root_id) byRoot.set(p.root_id, [...(byRoot.get(p.root_id) ?? []), p]);
  const out: { p: NPost; depth: number; orphanRoot?: string }[] = [];
  const done = new Set<string>();
  for (const p of posts) {
    if (!p.root_id) {
      out.push({ p, depth: 0 });
      for (const r of byRoot.get(p.id) ?? []) out.push({ p: r, depth: 1 });
      done.add(p.id);
    } else if (!ids.has(p.root_id) && !done.has(p.root_id)) {
      done.add(p.root_id);
      (byRoot.get(p.root_id) ?? []).forEach((r, i) => out.push({ p: r, depth: 1, ...(i === 0 ? { orphanRoot: p.root_id } : {}) }));
    }
  }
  return out;
}

const fileLine = (f: NFile) => `${f.name}${f.id ? ` (file_id=${f.id}${f.size !== undefined ? `, ${f.size}B` : ""})` : ""}`;
/** Bản markdown của lịch sử chat. */
export function renderExportMd(title: string, posts: NPost[], mode: ThreadMode, maxMsg = 20_000): string {
  const out: string[] = [title, ""];
  let day = "";
  for (const { p, depth, orphanRoot } of orderPosts(posts, mode)) {
    const d = dayOf(p.at);
    // nested: tiêu đề ngày theo tin gốc / nhóm trả lời, không chen giữa một luồng
    if ((depth === 0 || orphanRoot) && d !== day) { day = d; out.push(`## ${d}`, ""); }
    if (orphanRoot) out.push(`- (trả lời trong luồng #${orphanRoot}, tin gốc trước khoảng thời gian này)`);
    const pad = depth ? "    " : "";
    const tags = [p.edit_at ? `sửa ${fmtTime(p.edit_at)}` : "", p.pinned ? "đã ghim" : "", p.priority ? (p.priority === "urgent" ? "KHẨN" : "QUAN TRỌNG") : "",
      mode === "inline" && p.root_id ? `trả lời luồng #${p.root_id}` : "", !p.root_id && p.reply_count ? `luồng ${p.reply_count} trả lời` : ""].filter(Boolean);
    const msg = clipTo(p.message.trim(), maxMsg).replace(/\n/g, `\n${pad}  `);
    out.push(`${pad}- [${hhmm(p.at)}] **${p.user}** #${p.id}${tags.length ? ` (${tags.join(", ")})` : ""}: ${msg || "(không có chữ)"}`);
    for (const f of p.files) out.push(`${pad}  - tệp: ${fileLine(f)}`);
    if (p.poll) out.push(`${pad}  - bình chọn: ${p.poll}`);
    if (p.reactions.length) out.push(`${pad}  - cảm xúc: ${p.reactions.map((r) => `:${r.emoji}: ${r.users.join(", ")}`).join(" · ")}`);
  }
  return out.join("\n") + "\n";
}
/** Mỗi dòng một tin (JSON). */
export function renderExportJsonl(posts: NPost[], mode: ThreadMode, maxMsg = 20_000): string {
  return orderPosts(posts, mode).map(({ p }) => JSON.stringify({
    id: p.id, at: new Date(p.at).toISOString(), user_id: p.user_id || undefined, user: p.user, root_id: p.root_id || undefined,
    message: p.message.length > maxMsg ? p.message.slice(0, maxMsg) : p.message, edited_at: p.edit_at ? new Date(p.edit_at).toISOString() : undefined,
    reply_count: p.reply_count, pinned: p.pinned, priority: p.priority, poll: p.poll,
    files: p.files.length ? p.files : undefined, reactions: p.reactions.length ? p.reactions : undefined,
  })).join("\n") + "\n";
}
/** Số liệu tóm tắt của một lần xuất. */
export function stats(posts: NPost[]) {
  const people = new Map<string, number>();
  for (const p of posts) people.set(p.user, (people.get(p.user) ?? 0) + 1);
  return {
    total: posts.length, roots: posts.filter((p) => !p.root_id).length, replies: posts.filter((p) => p.root_id).length,
    files: posts.reduce((n, p) => n + p.files.length, 0), edited: posts.filter((p) => p.edit_at).length,
    people: [...people].sort((a, b) => b[1] - a[1]),
    first: posts[0]?.at, last: posts[posts.length - 1]?.at,
  };
}

// ---------------------------------------------------------------- bản ghi (transcript)
export type Role = "user" | "assistant" | "tool" | "result" | "system" | "error";
export interface Entry { at?: number; role: Role; text: string }
const ROLE_NAME: Record<Role, string> = { user: "Người dùng", assistant: "Trợ lý", tool: "Công cụ", result: "Kết quả", system: "Hệ thống", error: "Lỗi" };
const oneLineJson = (v: any, n: number) => { let s: string; try { s = typeof v === "string" ? v : JSON.stringify(v); } catch { s = String(v); } return clipTo(s.replace(/\s+/g, " ").trim(), n); };
const textOfBlocks = (c: any): string => typeof c === "string" ? c : Array.isArray(c) ? c.map((b: any) => (typeof b === "string" ? b : b?.type === "text" || b?.type === "input_text" || b?.type === "output_text" ? b.text ?? "" : "")).filter(Boolean).join("\n") : "";
/** Lời nhắc hệ thống / ngữ cảnh do runner hay CLI chèn (không phải lời người dùng). */
const isScaffold = (t: string) => /^\s*(<(environment_context|user_instructions|system-reminder|local-command|command-name|INSTRUCTIONS)|# AGENTS\.md instructions|<permissions instructions>)/.test(t);

/** Claude Code: ~/.claude/projects/<thư mục>/<session>.jsonl. */
export function parseClaudeJsonl(src: string): Entry[] {
  const out: Entry[] = [];
  for (const line of src.split("\n")) {
    if (!line.trim()) continue;
    let r: any; try { r = JSON.parse(line); } catch { continue; }
    const at = Date.parse(r.timestamp ?? "") || undefined;
    if (r.type === "summary" && r.summary) { out.push({ at, role: "system", text: `(tóm tắt phiên: ${r.summary})` }); continue; }
    if (r.type === "system" && r.subtype === "compact_boundary") { out.push({ at, role: "system", text: "(ngữ cảnh đã được nén — compact)" }); continue; }
    if (r.type !== "user" && r.type !== "assistant") continue;
    if (r.isMeta) continue;
    const c = r.message?.content;
    if (typeof c === "string") {
      if (c.trim()) out.push({ at, role: r.isCompactSummary ? "system" : isScaffold(c) ? "system" : r.type, text: c.trim() });
      continue;
    }
    for (const b of Array.isArray(c) ? c : []) {
      if (b?.type === "text" && String(b.text ?? "").trim()) out.push({ at, role: r.isCompactSummary || isScaffold(b.text) ? "system" : r.type, text: String(b.text).trim() });
      else if (b?.type === "tool_use") out.push({ at, role: "tool", text: `${b.name}(${oneLineJson(b.input ?? {}, 1500)})` });
      else if (b?.type === "tool_result") {
        const t = textOfBlocks(b.content) || (typeof b.content === "string" ? b.content : "");
        out.push({ at, role: b.is_error ? "error" : "result", text: t.trim() || "(trống)" });
      }
    }
  }
  return out;
}

/** Codex: <CODEX_HOME>/sessions/YYYY/MM/DD/rollout-<giờ>-<thread>.jsonl. */
export function parseCodexRollout(src: string): Entry[] {
  const out: Entry[] = [];
  for (const line of src.split("\n")) {
    if (!line.trim()) continue;
    let r: any; try { r = JSON.parse(line); } catch { continue; }
    const at = Date.parse(r.timestamp ?? "") || undefined;
    const p = r.payload ?? {};
    if (r.type === "compacted") { out.push({ at, role: "system", text: "(ngữ cảnh đã được nén — compact)" }); continue; }
    if (r.type === "event_msg" && p.type === "task_complete" && p.error?.message) { out.push({ at, role: "error", text: String(p.error.message) }); continue; }
    if (r.type !== "response_item") continue;
    if (p.type === "message") {
      if (p.role === "developer" || p.role === "system") continue;
      const t = textOfBlocks(p.content).trim();
      if (!t) continue;
      out.push({ at, role: p.role === "assistant" ? "assistant" : isScaffold(t) ? "system" : "user", text: t });
    } else if (p.type === "reasoning") {
      const s = (p.summary ?? []).map((x: any) => x?.text ?? "").filter(Boolean).join("\n").trim();
      if (s) out.push({ at, role: "system", text: `(suy nghĩ) ${s}` });
    } else if (/_call$/.test(p.type ?? "")) {
      const name = p.name ?? p.type.replace(/_call$/, "");
      const args = p.arguments ?? p.input ?? p.action ?? p.query ?? {};
      out.push({ at, role: "tool", text: `${name}(${oneLineJson(args, 1500)})` });
    } else if (/_call_output$/.test(p.type ?? "")) {
      const o = p.output;
      const t = typeof o === "string" ? o : Array.isArray(o) ? textOfBlocks(o) : o?.content ?? oneLineJson(o, 4000);
      out.push({ at, role: "result", text: String(t).trim() || "(trống)" });
    }
  }
  return out;
}

// ---- Antigravity: ~/.gemini/antigravity-cli/conversations/<id>.db (SQLite, mỗi bước một protobuf) ----
interface PbField { f: number; v?: number; s?: string; m?: PbField[]; n: number }
const printable = (s: string) => { let bad = 0; for (const ch of s) { const c = ch.codePointAt(0)!; if ((c < 32 && c !== 9 && c !== 10 && c !== 13) || c === 0xfffd) bad++; } return bad === 0; };
/** Giải protobuf không cần schema: chuỗi in được thì coi là chuỗi, còn lại thử như message lồng. */
export function pbDecode(b: Uint8Array, depth = 0): PbField[] | null {
  const out: PbField[] = [];
  let i = 0;
  const varint = (): number => { let r = 0, mul = 1; for (let k = 0; k < 10; k++) { if (i >= b.length) throw 0; const c = b[i++]; r += (c & 0x7f) * mul; mul *= 128; if (!(c & 0x80)) return r; } throw 0; };
  try {
    while (i < b.length) {
      const key = varint(), f = Math.floor(key / 8), w = key % 8;
      if (f < 1) return null;
      if (w === 0) out.push({ f, v: varint(), n: 0 });
      else if (w === 1) { i += 8; if (i > b.length) return null; }
      else if (w === 5) { i += 4; if (i > b.length) return null; }
      else if (w === 2) {
        const n = varint();
        if (i + n > b.length) return null;
        const sub = b.subarray(i, i + n); i += n;
        let s: string | null = null;
        try { s = new TextDecoder("utf-8", { fatal: true }).decode(sub); } catch {}
        // Chuỗi in được thì là chuỗi; riêng chuỗi mở đầu bằng "\n" (= thẻ field 1 kiểu bytes) mà giải được như message thì là message.
        const m = depth < 12 && (s === null || !printable(s) || sub[0] === 0x0a) ? pbDecode(sub, depth + 1) : null;
        if (m && m.length) out.push({ f, m, n });
        else if (s !== null && printable(s)) out.push({ f, s, n });
        else out.push({ f, n });
      } else return null;
    }
  } catch { return null; }
  return out;
}
const isIdLike = (s: string) => /^[0-9a-f-]{20,}$/i.test(s) || /^(toolu|call|req|bot|t)[-_]/.test(s) || /^[A-Za-z0-9+/=]{40,}$/.test(s) || /^-?\d+$/.test(s) || /^file:\/\//.test(s) || /^type\.googleapis\.com/.test(s);
const firstTs = (fs: PbField[] | undefined): number | undefined => {
  for (const x of fs ?? []) {
    if (x.v !== undefined && x.v > 1.6e9 && x.v < 2.2e9) return x.v * 1000;
    const t = firstTs(x.m); if (t) return t;
  }
  return undefined;
};
const strs = (fs: PbField[] | undefined) => (fs ?? []).filter((x) => x.s !== undefined && x.s.trim().length > 1 && !isIdLike(x.s));
/** Lời gọi tool trong một message: con có chuỗi id (toolu_ / call_), tên, đối số JSON. */
function toolCalls(fs: PbField[] | undefined, out: string[] = [], depth = 0): string[] {
  for (const x of fs ?? []) {
    if (!x.m) continue;
    const kids = x.m.filter((k) => k.s !== undefined);
    const id = kids.find((k) => /^(toolu|call)[-_]/.test(k.s!));
    const args = kids.find((k) => k.s!.trim().startsWith("{"));
    const name = kids.find((k) => k !== id && k !== args && /^[\w.:-]{2,64}$/.test(k.s!));
    if (id && (name || args)) {
      let label = name?.s ?? "tool", a = args?.s ?? "";
      try { const j = JSON.parse(a); if (j?.ToolName) { label = `${j.ServerName ?? "mcp"} · ${j.ToolName}`; a = JSON.stringify(j.Arguments ?? {}); } else a = JSON.stringify(j); } catch {}
      out.push(`${label}(${oneLineJson(a, 1500)})`);
    } else if (depth < 3) toolCalls(x.m, out, depth + 1);
  }
  return out;
}
/** Các bước của một hội thoại Antigravity -> bản ghi (cố gắng hết mức: định dạng nội bộ, không có schema công khai). */
export function parseAgySteps(rows: { idx: number; step_type: number; step_payload: Uint8Array | null }[]): Entry[] {
  const out: Entry[] = [];
  for (const r of rows) {
    if (!r.step_payload) continue;
    const top = pbDecode(r.step_payload instanceof Uint8Array ? r.step_payload : new Uint8Array(r.step_payload as any));
    if (!top) continue;
    const at = firstTs(top.find((x) => x.f === 5)?.m) ?? firstTs(top);
    // Nội dung riêng của bước: field message lớn nhất ngoài metadata (5).
    const content = top.filter((x) => x.m && x.f !== 5).sort((a, b) => b.n - a.n)[0]?.m;
    const direct = strs(content);
    const longest = [...direct].sort((a, b) => b.s!.length - a.s!.length)[0]?.s?.trim() ?? "";
    switch (r.step_type) {
      case 14: { // lời người dùng (lượt đầu có kèm hướng dẫn hệ thống)
        if (!longest) break;
        out.push({ at, role: /^<system_instructions>/.test(longest) ? "system" : "user", text: longest });
        break;
      }
      case 15: { // trợ lý: chữ trả lời (field 1), suy nghĩ (field 3, bỏ), lời gọi tool
        const t = direct.find((x) => x.f === 1)?.s?.trim();
        if (t) out.push({ at, role: "assistant", text: t });
        for (const c of toolCalls(content)) out.push({ at, role: "tool", text: c });
        break;
      }
      case 132: { // kết quả tool: content.2.1 (đối số ở content.1, lời gọi đã ghi ở bước của trợ lý)
        const res = content?.find((x) => x.f === 2 && x.m)?.m?.find((y) => y.f === 1 && y.s !== undefined)?.s?.trim()
          ?? direct.filter((x) => !x.s!.trim().startsWith("{") && !/^(auto_approve|allow|deny)$/.test(x.s!)).map((x) => x.s!.trim()).sort((a, b) => b.length - a.length)[0];
        if (res) out.push({ at, role: "result", text: res });
        break;
      }
      case 17: if (longest) out.push({ at, role: "error", text: direct[0]?.s?.trim() ?? longest }); break;
      case 101: if (longest) out.push({ at, role: "system", text: direct[0]?.s?.trim() ?? longest }); break;
    }
  }
  return out;
}
export function parseAgyDb(path: string): Entry[] {
  const read = (p: string, readonly = true) => {
    const db = readonly ? new Database(p, { readonly: true }) : new Database(p);
    try { return parseAgySteps(db.query("SELECT idx, step_type, step_payload FROM steps ORDER BY idx").all() as any); }
    finally { db.close(); }
  };
  try { return read(path); } catch {
    // Tệp ở chế độ WAL không mở chỉ-đọc được khi thiếu -shm (agy đã tắt): đọc trên bản sao (kèm -wal nếu có).
    const dir = mkdtempSync(join(tmpdir(), "agy-tr-"));
    try {
      const copy = join(dir, "c.db");
      copyFileSync(path, copy);
      if (existsSync(`${path}-wal`)) copyFileSync(`${path}-wal`, `${copy}-wal`);
      return read(copy, false); // bản sao riêng: mở ghi được để SQLite tạo -shm
    } finally { rmSync(dir, { recursive: true, force: true }); }
  }
}

/** Kênh phiên AI trên Flygo Chat -> bản ghi: tin người dùng, câu trả lời của bot, thẻ bước (tóm tắt) xen theo seg. */
export function renderChatTranscript(posts: any[], botId: string, names: Map<string, string>): Entry[] {
  const out: Entry[] = [];
  let lastBotText = "";
  for (const p of [...posts].sort((a, b) => a.create_at - b.create_at)) {
    if (p.type && String(p.type).startsWith("system_")) continue;
    if (p.props?.flygo_agent_approval) continue;
    const am = p.props?.flygo_agent_message;
    if (am?.streaming) continue;
    const at = p.create_at;
    const files = (p.metadata?.files ?? []).map((f: any) => f.name);
    const fileNote = files.length ? `\n[tệp: ${files.join(", ")}]` : "";
    const card = p.props?.flygo_agent;
    if (p.user_id === botId && card && typeof card === "object") {
      const steps: any[] = Array.isArray(card.steps) ? card.steps : [];
      const texts: string[] = Array.isArray(card.texts) ? card.texts.map(String) : [];
      const stepLine = (s: any) => `${s.status === "error" ? "✗" : s.status === "done" ? "✓" : "…"} ${s.label || s.title}${s.status === "error" && s.detail ? ` — ${String(s.detail).replace(/\s+/g, " ").slice(0, 200)}` : ""}`;
      const group = (ss: any[]) => { if (ss.length) out.push({ at, role: "tool", text: `${ss.length} bước: ${ss.map(stepLine).join(" · ")}` }); };
      if (texts.length) {
        for (let i = 0; i <= texts.length; i++) {
          group(steps.filter((s) => (s.seg ?? 0) === i || (i === texts.length && (s.seg ?? 0) > texts.length)));
          if (i < texts.length && texts[i].trim()) out.push({ at, role: "assistant", text: texts[i].trim() });
        }
        lastBotText = texts[texts.length - 1]?.trim() ?? "";
      } else {
        group(steps);
        const m = String(p.message ?? "").trim();
        if (am && m) { out.push({ at, role: "assistant", text: m }); lastBotText = m; }
      }
      if (card.status === "error" && card.error) out.push({ at, role: "error", text: String(card.error) });
      if (card.status === "cancelled" || card.status === "stopped") out.push({ at, role: "system", text: `(lượt ${card.status === "cancelled" ? "bị dừng" : "dừng vì runner tắt"})` });
      continue;
    }
    if (p.props?.flygo_agent) continue;
    const m = String(p.message ?? "").trim();
    if (!m && !files.length) continue;
    if (p.user_id === botId) {
      if (m && m === lastBotText) continue; // câu trả lời cuối đã có trong thẻ
      out.push({ at, role: "assistant", text: m + fileNote });
    } else out.push({ at, role: "user", text: `${names.get(p.user_id) ?? p.user_id}: ${m}${fileNote}` });
  }
  return out;
}

/** Một mục bản ghi thành chữ (đã che bí mật, cắt theo loại). */
export function renderEntry(e: Entry, i: number, caps = { text: 8000, tool: 600, result: 800 }): string {
  const cap = e.role === "tool" ? caps.tool : e.role === "result" || e.role === "error" ? caps.result : caps.text;
  return `[${i}${e.at ? ` · ${fmtTime(e.at)}` : ""}] ${ROLE_NAME[e.role]}: ${clipTo(redact(e.text), cap)}`;
}
/**
 * Phân trang theo ký tự. part=last: các mục cuối (trước before_entry) vừa max_chars; part=all: từ from_entry trở đi.
 * Trả chữ + chỉ số mục đầu / cuối đã lấy (để gọi tiếp).
 */
export function pageEntries(entries: Entry[], o: { part: "last" | "all"; maxChars: number; fromEntry?: number; beforeEntry?: number; caps?: { text: number; tool: number; result: number } }) {
  const n = entries.length;
  const lines: string[] = [];
  let used = 0, a = 0, b = -1;
  if (o.part === "all") {
    a = Math.min(Math.max(0, o.fromEntry ?? 0), n);
    for (let i = a; i < n; i++) {
      const s = renderEntry(entries[i], i, o.caps);
      if (lines.length && used + s.length + 1 > o.maxChars) break;
      lines.push(s.length > o.maxChars ? s.slice(0, o.maxChars) : s); used += s.length + 1; b = i;
    }
  } else {
    const end = Math.min(Math.max(0, o.beforeEntry ?? n), n);
    b = end - 1; a = end;
    for (let i = end - 1; i >= 0; i--) {
      const s = renderEntry(entries[i], i, o.caps);
      if (lines.length && used + s.length + 1 > o.maxChars) break;
      lines.unshift(s.length > o.maxChars ? s.slice(0, o.maxChars) : s); used += s.length + 1; a = i;
    }
  }
  return { text: lines.join("\n"), first: a, last: b, total: n };
}
