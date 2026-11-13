import { expect, test } from "bun:test";
import { claudeReadOnly, codexServers, desktopMcp, desktopPersona } from "./desktop-mcp";

test("computerUse=false disables everything", () => {
  const d = desktopMcp({ computerUse: false });
  expect(d.servers).toEqual({});
  expect(desktopPersona(d, "h")).toBe("");
});

test("custom server and disabling a known one", () => {
  const d = desktopMcp({ desktopMcp: { "my-desktop": { command: "/bin/echo", args: ["mcp"] }, "cua-driver": false, tmux: false, peekaboo: false } });
  expect(d.servers["my-desktop"]).toEqual({ command: "/bin/echo", args: ["mcp"] });
  expect(d.servers["cua-driver"]).toBeUndefined();
  const cx = codexServers(d)["my-desktop"] as any;
  expect(cx.default_tools_approval_mode).toBe("prompt");
  expect(cx.tools).toBeUndefined();
  expect(claudeReadOnly(d)).toEqual([]);
});
