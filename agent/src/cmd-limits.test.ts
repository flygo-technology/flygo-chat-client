import { expect, test } from "bun:test";
import { badgeOf, commandLimit, limitBadge } from "./cmd-limits";

test("hạn của lệnh: timeout_sec > từ ước tính (max(3×, 30)) > mặc định; trần commandTimeoutMaxSec", () => {
  expect(commandLimit({ expected_sec: 20 }, 120, 1800)).toEqual({ sec: 60, expected: 20, source: "expected", capped: false });
  expect(commandLimit({ expected_sec: 3 }, 120, 1800).sec).toBe(30);
  expect(commandLimit({ expected_sec: 20, timeout_sec: 45 }, 120, 1800)).toEqual({ sec: 45, expected: 20, source: "timeout", capped: false });
  expect(commandLimit({}, 120, 1800)).toEqual({ sec: 120, source: "default", capped: false });
  expect(commandLimit({ timeout_sec: 99999 }, 120, 1800)).toMatchObject({ sec: 1800, capped: true });
  expect(commandLimit({ timeout_sec: "abc", expected_sec: -1 }, 120, 1800).source).toBe("default");
});

test("nhãn trên thẻ", () => {
  expect(limitBadge({ sec: 60, expected: 20 })).toBe("⏱ dự kiến 20 s · giới hạn 60 s");
  expect(badgeOf("mcp__flygo_chat__run_command", { command: "x", expected_sec: 10 })).toBe("⏱ dự kiến 10 s · giới hạn 30 s");
  expect(badgeOf("Bash", { command: "x", timeout: 90000 })).toBe("⏱ giới hạn 90 s");
  expect(badgeOf("Bash", { command: "x", run_in_background: true })).toBeNull();
  expect(badgeOf("Read", { file_path: "/x" })).toBeNull();
});
