import { expect, test } from "bun:test";
import { agyLimits, claudeLimits, codexLimits, limitsKey, mergeCodexUpdate, toEpochSec, windowIdFor } from "./limits";

// Kết quả account/rateLimits/read thật của codex-cli 0.162 (gói plus).
const codexRead = {
  ordinaryUsageAllowed: true,
  rateLimits: { limitId: "codex", limitName: null, primary: { usedPercent: 0, windowDurationMins: 300, resetsAt: 1793806429 }, secondary: { usedPercent: 16, windowDurationMins: 10080, resetsAt: 1794371558 }, credits: { hasCredits: false, unlimited: false, balance: "0" }, planType: "plus", rateLimitReachedType: null, spendControlReached: false },
  rateLimitsByLimitId: {
    codex: { limitId: "codex", primary: { usedPercent: 0, windowDurationMins: 300, resetsAt: 1793806429 }, secondary: { usedPercent: 16, windowDurationMins: 10080, resetsAt: 1794371558 }, planType: "plus" },
    codex_spark: { limitId: "codex_spark", limitName: "GPT Spark", primary: { usedPercent: 40, windowDurationMins: 300, resetsAt: 1793806000 } },
  },
};

test("codex: read response -> 5h + weekly windows, extra bucket labelled", () => {
  const l = codexLimits(codexRead, 1)!;
  expect(l.engine).toBe("codex");
  expect(l.plan).toBe("plus");
  expect(l.reached).toBeUndefined();
  expect(l.windows).toEqual([
    { id: "five_hour", usedPercent: 0, windowMins: 300, resetsAt: 1793806429 },
    { id: "seven_day", usedPercent: 16, windowMins: 10080, resetsAt: 1794371558 },
    { id: "codex_spark:five_hour", label: "GPT Spark", usedPercent: 40, windowMins: 300, resetsAt: 1793806000 },
  ]);
  expect(codexLimits(null)).toBeNull();
  expect(codexLimits({ rateLimits: { limitId: "codex" } })).toBeNull(); // tài khoản API key: không có cửa sổ
});

test("codex: sparse rateLimits/updated keeps previous values", () => {
  const merged = mergeCodexUpdate(codexRead, { limitId: "codex", primary: { usedPercent: 7, windowDurationMins: 300, resetsAt: 1793806429 }, secondary: null, planType: null });
  const l = codexLimits(merged)!;
  expect(l.windows[0].usedPercent).toBe(7);
  expect(l.windows[1].usedPercent).toBe(16);
  expect(l.plan).toBe("plus");
  expect(codexLimits(mergeCodexUpdate(null, { primary: { usedPercent: 3, windowDurationMins: 300 } }))!.windows[0]).toEqual({ id: "five_hour", usedPercent: 3, windowMins: 300 });
  expect(codexLimits({ ...codexRead, rateLimits: { ...codexRead.rateLimits, rateLimitReachedType: "rate_limit_reached" } })!.reached).toBe(true);
});

test("claude: rate_limit_event unifiedWindows (fraction) -> percent, merged across events", () => {
  const a = claudeLimits({ status: "allowed", unifiedWindows: { five_hour: { utilization: 0.234, resetsAt: 1793806429, status: "allowed" }, seven_day: { utilization: 0.81, resetsAt: 1794371558 } } }, null, 5)!;
  expect(a.engine).toBe("claude");
  expect(a.windows).toEqual([
    { id: "five_hour", usedPercent: 23, windowMins: 300, resetsAt: 1793806429, status: "allowed" },
    { id: "seven_day", usedPercent: 81, windowMins: 10080, resetsAt: 1794371558 },
  ]);
  // Sự kiện sau chỉ báo cửa sổ tuần (kiểu cũ, không có unifiedWindows): giữ cửa sổ 5 giờ.
  const b = claudeLimits({ status: "rejected", rateLimitType: "seven_day", utilization: 1, resetsAt: 1794371558 }, a)!;
  expect(b.reached).toBe(true);
  expect(b.windows.map((w) => [w.id, w.usedPercent])).toEqual([["five_hour", 23], ["seven_day", 100]]);
  // Không có số liệu: giữ nguyên.
  expect(claudeLimits({ status: "allowed" }, null)).toBeNull();
  expect(claudeLimits(undefined, a)).toBe(a);
});

test("agy: quota_info with remaining_fraction when present, else null", () => {
  expect(agyLimits({ event: "result", result: { usage: { input_tokens: 1 } } })).toBeNull();
  const l = agyLimits({ event: "result", result: { quota_info: [{ display_name: "Gemini 3 Pro", remaining_fraction: 0.25, reset_time: "2026-11-04T10:00:00Z" }] } })!;
  expect(l.windows).toEqual([{ id: "agy:gemini_3_pro", label: "Gemini 3 Pro", usedPercent: 75, resetsAt: Date.parse("2026-11-04T10:00:00Z") / 1000 }]);
});

test("helpers", () => {
  expect(windowIdFor(300)).toBe("five_hour");
  expect(windowIdFor(10080)).toBe("seven_day");
  expect(windowIdFor(60)).toBe("60m");
  expect(toEpochSec(1793806429000)).toBe(1793806429);
  expect(toEpochSec("1793806429")).toBe(1793806429);
  expect(toEpochSec(null)).toBeUndefined();
  expect(limitsKey(codexLimits(codexRead, 1))).toBe(limitsKey(codexLimits(codexRead, 2)));
});
