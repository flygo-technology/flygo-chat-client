import { expect, test } from "bun:test";
import { resolvePermMode } from "./perm-mode";

const modes = ["manual", "acceptEdits", "plan", "auto", "bypassPermissions"] as const;
const base = { modes, canBypass: true, forcedManual: false };

test("phiên mới không gửi chế độ: dùng chế độ toàn quyền chủ bot đã chọn", () => {
  expect(resolvePermMode({ ...base, owner: true, remembered: "bypassPermissions" })).toEqual({ mode: "bypassPermissions" });
});
test("chủ bot chọn rõ: dùng và nhớ", () => {
  expect(resolvePermMode({ ...base, owner: true, want: "bypassPermissions", remembered: "manual" })).toEqual({ mode: "bypassPermissions", remember: "bypassPermissions" });
  expect(resolvePermMode({ ...base, owner: true, want: "manual", remembered: "bypassPermissions" })).toEqual({ mode: "manual", remember: "manual" });
});
test("người không phải chủ bot: không bao giờ toàn quyền, không dùng chế độ đã nhớ", () => {
  expect(resolvePermMode({ ...base, owner: false, remembered: "bypassPermissions" })).toEqual({ mode: undefined });
  expect(resolvePermMode({ ...base, owner: false, want: "bypassPermissions" }).bad).toBe("chế độ bypassPermissions");
  expect(resolvePermMode({ ...base, owner: false, want: "plan" })).toEqual({ mode: "plan" });
});
test("đã \"bật lại duyệt\" trong phạm vi: toàn quyền không áp dụng", () => {
  expect(resolvePermMode({ ...base, owner: true, remembered: "bypassPermissions", forcedManual: true })).toEqual({ mode: undefined });
  expect(resolvePermMode({ ...base, owner: true, want: "bypassPermissions", forcedManual: true })).toEqual({ mode: undefined, remember: "bypassPermissions" });
  expect(resolvePermMode({ ...base, owner: true, want: "acceptEdits", forcedManual: true })).toEqual({ mode: "acceptEdits", remember: "acceptEdits" });
});
test("codex: không có toàn quyền", () => {
  expect(resolvePermMode({ ...base, canBypass: false, owner: true, remembered: "bypassPermissions" })).toEqual({ mode: undefined });
});
