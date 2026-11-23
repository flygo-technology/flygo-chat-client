// Thời hạn của lệnh do agent tự đặt (Sếp 2026-11-23: hạn cố định 120 s "có vẻ không ổn" — agent ước tính từng lệnh).
//   expected_sec: agent ước tính; timeout_sec: hạn cứng (thiếu thì max(3 × ước tính, 30)); không có cả hai thì hạn mặc định của bot.
//   Hạn tối đa: commandTimeoutMaxSec của bot (mặc định 1800).
export const envDefaultSec = () => Math.min(envMaxSec(), Math.max(5, Number(process.env.FLYGO_CMD_TIMEOUT_SEC) || 120));
export const envMaxSec = () => Math.max(30, Number(process.env.FLYGO_CMD_TIMEOUT_MAX_SEC) || 1800);

export interface Limit { sec: number; expected?: number; source: "timeout" | "expected" | "default"; capped: boolean }

export function commandLimit(a: { timeout_sec?: unknown; expected_sec?: unknown }, def = envDefaultSec(), max = envMaxSec()): Limit {
  const num = (v: unknown) => { const n = Number(v); return Number.isFinite(n) && n > 0 ? n : undefined; };
  const exp = num(a.expected_sec), to = num(a.timeout_sec);
  const raw = to ?? (exp !== undefined ? Math.max(3 * exp, 30) : def);
  const sec = Math.max(1, Math.min(max, Math.round(raw)));
  return { sec, ...(exp !== undefined ? { expected: Math.round(exp) } : {}), source: to !== undefined ? "timeout" : exp !== undefined ? "expected" : "default", capped: raw > max };
}

/** Nhãn trên thẻ: "⏱ dự kiến 20 s · giới hạn 60 s" (hoặc chỉ giới hạn). */
export const limitBadge = (l: { sec: number; expected?: number }) => `⏱ ${l.expected !== undefined ? `dự kiến ${l.expected} s · ` : ""}giới hạn ${l.sec} s`;

/** Nhãn hạn từ input của tool lệnh (run_command của runner: giây; Bash của Claude Code: timeout ms). null nếu không phải tool lệnh. */
export function badgeOf(tool: string, input: any): string | null {
  if (tool === "Bash") {
    if (input?.run_in_background) return null;
    const ms = Number(input?.timeout);
    return limitBadge({ sec: Math.round((Number.isFinite(ms) && ms > 0 ? ms : envDefaultSec() * 1000) / 1000) });
  }
  if (/(^|__)run_command$/.test(tool)) return limitBadge(commandLimit(input ?? {}));
  return null;
}
