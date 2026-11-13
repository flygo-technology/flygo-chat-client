// Hạn mức sử dụng của tài khoản engine (Codex: cửa sổ 5 giờ / tuần; Claude Code: phiên 5 giờ / tuần; agy: quota nếu có).
// Runner gửi lên app trong thẻ tiến trình (flygo_agent.usage.limits) và props.flygo_models.limits của bot.

export interface LimitWindow {
  id: string; // five_hour | seven_day | seven_day_opus | … | "<bucket>:<cửa sổ>" | "<số phút>m"
  label?: string; // tên do engine đặt (bucket phụ của Codex, model của agy)
  usedPercent: number; // 0..100 (có thể >100 khi vượt)
  windowMins?: number;
  resetsAt?: number; // unix giây
  status?: string; // allowed | allowed_warning | rejected
}
export interface UsageLimits {
  engine: string;
  at: number; // ms, lúc đọc
  plan?: string;
  reached?: boolean; // engine báo đã chạm hạn mức
  windows: LimitWindow[];
}

const num = (v: any): number | undefined => (v == null || v === "" || !Number.isFinite(Number(v)) ? undefined : Number(v));
/** Thời điểm đặt lại → unix giây (nhận giây, mili giây hoặc chuỗi ISO). */
export function toEpochSec(v: any): number | undefined {
  if (v == null) return undefined;
  if (typeof v === "string" && !/^\d+(\.\d+)?$/.test(v.trim())) { const t = Date.parse(v); return Number.isFinite(t) ? Math.round(t / 1000) : undefined; }
  const n = num(v);
  if (n == null || n <= 0) return undefined;
  return Math.round(n > 1e12 ? n / 1000 : n);
}

/** Tên cửa sổ theo độ dài: 300 phút = five_hour, 10080 = seven_day, còn lại "<phút>m". */
export function windowIdFor(mins?: number): string {
  if (mins === 300) return "five_hour";
  if (mins === 10080) return "seven_day";
  if (mins === 1440) return "daily";
  return mins ? `${mins}m` : "window";
}

const pct = (v: any) => Math.max(0, Math.round(Number(v) || 0));

// ---------------------------------------------------------------- Codex
function codexWindow(w: any, prefix: string, label?: string): LimitWindow | null {
  if (!w || w.usedPercent == null) return null;
  const mins = num(w.windowDurationMins);
  return { id: `${prefix}${windowIdFor(mins)}`, ...(label ? { label } : {}), usedPercent: pct(w.usedPercent), ...(mins ? { windowMins: mins } : {}), ...(toEpochSec(w.resetsAt) ? { resetsAt: toEpochSec(w.resetsAt) } : {}) };
}

/** Kết quả account/rateLimits/read (hoặc một RateLimitSnapshot) của `codex app-server` → hạn mức. null nếu không có cửa sổ nào. */
export function codexLimits(res: any, at = Date.now()): UsageLimits | null {
  if (!res) return null;
  const main = res.rateLimits ?? (res.primary || res.secondary ? res : null);
  const buckets: any[] = res.rateLimitsByLimitId ? Object.values(res.rateLimitsByLimitId) : [];
  const mainId = main?.limitId ?? "codex";
  const windows: LimitWindow[] = [];
  const add = (snap: any, extra: boolean) => {
    const prefix = extra ? `${snap.limitId ?? "x"}:` : "";
    const label = extra ? String(snap.limitName ?? snap.limitId ?? "") || undefined : undefined;
    for (const w of [snap?.primary, snap?.secondary]) { const x = codexWindow(w, prefix, label); if (x && !windows.some((y) => y.id === x.id)) windows.push(x); }
  };
  if (main) add(main, false);
  for (const b of buckets) if (b && (b.limitId ?? "codex") !== mainId) add(b, true);
  if (!windows.length) return null;
  const reached = !!main?.rateLimitReachedType || main?.spendControlReached === true || res.ordinaryUsageAllowed === false;
  return { engine: "codex", at, ...(main?.planType ? { plan: String(main.planType) } : {}), ...(reached ? { reached } : {}), windows };
}

/** account/rateLimits/updated (cập nhật thưa): gộp vào bản đọc gần nhất, trường null/thiếu giữ giá trị cũ. */
export function mergeCodexUpdate(prev: any, snap: any): any {
  if (!snap) return prev;
  const keep = (a: any, b: any) => { const o = { ...(a ?? {}) }; for (const [k, v] of Object.entries(b ?? {})) if (v != null) o[k] = v; return o; };
  const base = prev ?? { rateLimits: {} };
  const id = snap.limitId ?? base.rateLimits?.limitId ?? "codex";
  const out = { ...base };
  if (!base.rateLimits?.limitId || base.rateLimits.limitId === id) out.rateLimits = keep(base.rateLimits, snap);
  if (base.rateLimitsByLimitId) out.rateLimitsByLimitId = { ...base.rateLimitsByLimitId, [id]: keep(base.rateLimitsByLimitId[id], snap) };
  return out;
}

// ---------------------------------------------------------------- Claude Code
const CLAUDE_MINS: Record<string, number> = { five_hour: 300, seven_day: 10080, seven_day_opus: 10080, seven_day_sonnet: 10080, seven_day_overage_included: 10080 };

/** rate_limit_event.rate_limit_info của `claude -p --output-format stream-json` → hạn mức (gộp với lần trước:
 *  sự kiện chỉ báo cửa sổ vừa đổi). utilization là phần (0..1). */
export function claudeLimits(info: any, prev: UsageLimits | null, at = Date.now()): UsageLimits | null {
  if (!info || typeof info !== "object") return prev;
  const map = new Map<string, LimitWindow>((prev?.windows ?? []).map((w) => [w.id, w]));
  const put = (id: string, w: any) => {
    const u = num(w?.utilization);
    if (u == null) return;
    const old = map.get(id);
    map.set(id, { id, usedPercent: pct(u * 100), ...(CLAUDE_MINS[id] ? { windowMins: CLAUDE_MINS[id] } : {}), ...((toEpochSec(w.resetsAt) ?? old?.resetsAt) ? { resetsAt: toEpochSec(w.resetsAt) ?? old?.resetsAt } : {}), ...(w.status ? { status: String(w.status) } : {}) });
  };
  for (const [id, w] of Object.entries<any>(info.unifiedWindows ?? {})) put(id, w);
  if (info.rateLimitType && info.utilization != null && info.rateLimitType !== "overage") put(info.rateLimitType, info);
  else if (info.rateLimitType && map.has(info.rateLimitType) && info.status) map.set(info.rateLimitType, { ...map.get(info.rateLimitType)!, status: String(info.status), ...(toEpochSec(info.resetsAt) ? { resetsAt: toEpochSec(info.resetsAt) } : {}) });
  if (!map.size) return prev;
  const order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_overage_included"];
  const windows = [...map.values()].sort((a, b) => (order.indexOf(a.id) + 1 || 99) - (order.indexOf(b.id) + 1 || 99));
  return { engine: "claude", at, ...(info.status === "rejected" ? { reached: true } : {}), windows };
}

// ---------------------------------------------------------------- Antigravity
/** Quota của agy nếu stream-json có (quota_info / remaining_fraction ở đâu đó trong sự kiện); không có → null. */
export function agyLimits(ev: any, at = Date.now()): UsageLimits | null {
  const windows: LimitWindow[] = [];
  const seen = new Set<any>();
  const walk = (o: any, name: string, depth: number) => {
    if (!o || typeof o !== "object" || depth > 6 || seen.has(o)) return;
    seen.add(o);
    if (Array.isArray(o)) { for (const x of o) walk(x, name, depth + 1); return; }
    const frac = num(o.remaining_fraction ?? o.remainingFraction);
    if (frac != null) {
      const label = String(o.display_name ?? o.displayName ?? o.label ?? o.model ?? o.model_id ?? name ?? "").trim() || undefined;
      const id = `agy:${(label ?? `q${windows.length}`).toLowerCase().replace(/[^\w.-]+/g, "_")}`;
      if (!windows.some((w) => w.id === id)) windows.push({ id, ...(label ? { label } : {}), usedPercent: pct((1 - frac) * 100), ...(toEpochSec(o.reset_time ?? o.resetTime ?? o.resets_at) ? { resetsAt: toEpochSec(o.reset_time ?? o.resetTime ?? o.resets_at) } : {}) });
      return;
    }
    for (const [k, v] of Object.entries(o)) walk(v, String(o.display_name ?? o.displayName ?? o.model ?? o.label ?? (/quota/i.test(k) ? name : k)), depth + 1);
  };
  walk(ev, "", 0);
  return windows.length ? { engine: "agy", at, windows } : null;
}

/** Khoá so sánh (bỏ thời điểm đọc): khỏi đăng lại khi hạn mức không đổi. */
export const limitsKey = (l: UsageLimits | null | undefined) => (l ? JSON.stringify({ ...l, at: 0 }) : "");
