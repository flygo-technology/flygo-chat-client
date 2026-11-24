import { expect, test } from "bun:test";
import { CLAUDE_ALIASES, parseClaudeModels } from "./engines/claude";

// Mẫu rút gọn từ `initialize` của Claude Code 2.1.331 (tài khoản Max).
const RAW = [
  { value: "default", resolvedModel: "claude-opus-5-5", displayName: "Default (recommended)", supportedEffortLevels: ["low", "medium", "high", "xhigh", "max"] },
  { value: "opus", resolvedModel: "claude-opus-5-5", displayName: "Opus 5.5", supportedEffortLevels: ["low", "medium", "high", "xhigh", "max"] },
  { value: "fable", resolvedModel: "claude-fable-5-2", displayName: "Fable 5.2", supportedEffortLevels: ["low", "medium", "high", "xhigh", "max"] },
  { value: "sonnet", resolvedModel: "claude-sonnet-5-5", displayName: "Sonnet 5.5" },
  { value: "claude-fable-5-1", displayName: "Fable 5.1" },
  { value: "claude-opus-5-5", displayName: "Opus 5.5 (trùng)" },
  { value: "mystery" },
];

test("đọc danh sách model của Claude Code: bỏ default, bí danh -> id đầy đủ, bỏ trùng", () => {
  const r = parseClaudeModels(RAW, "fable")!;
  expect(r.models.map((m) => m.id)).toEqual(["claude-opus-5-5", "claude-fable-5-2", "claude-sonnet-5-5", "claude-fable-5-1"]);
  expect(r.aliases).toEqual({ opus: "claude-opus-5-5", fable: "claude-fable-5-2", sonnet: "claude-sonnet-5-5" });
  expect(r.models.find((m) => m.isDefault)?.id).toBe("claude-fable-5-2");
  expect(r.models[1].name).toBe("Fable 5.2");
  expect(r.models[2].efforts).toEqual(["low", "medium", "high", "xhigh", "max"]); // không báo mức thì dùng mặc định
});

test("model mặc định theo id đầy đủ; dữ liệu hỏng thì null (dùng danh sách cố định)", () => {
  expect(parseClaudeModels(RAW, "claude-fable-5-1")!.models.find((m) => m.isDefault)?.id).toBe("claude-fable-5-1");
  expect(parseClaudeModels(undefined)).toBeNull();
  expect(parseClaudeModels([{ value: "default" }])).toBeNull();
});

test("danh sách cố định dự phòng đã có Fable 5.2", () => {
  expect(CLAUDE_ALIASES.fable).toBe("claude-fable-5-2");
});
