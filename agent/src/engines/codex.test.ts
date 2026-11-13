import { expect, test } from "bun:test";

test("codex: busy thread errors are recognised", async () => {
  const { isBusyThread } = await import("./codex");
  expect(isBusyThread("thread/resume: thread 01a152c7-983c-77b1-b232-7e247662ed1e already has an active writer")).toBe(true);
  expect(isBusyThread("model gpt-x is not supported")).toBe(false);
});

test("codex: sandbox network is on by default and can be turned off", async () => {
  const { codexAppServerArgs } = await import("../config");
  const base: any = { codex: { spawnArgs: ["-c", "x=1"] } };
  expect(codexAppServerArgs(base)).toEqual(["-c", "x=1", "-c", "sandbox_workspace_write.network_access=true"]);
  expect(codexAppServerArgs({ codex: { spawnArgs: [], network: false } } as any)).toEqual([]);
  expect(codexAppServerArgs({ codex: { spawnArgs: ["-c", "sandbox_workspace_write.network_access=false"] } } as any)).toEqual(["-c", "sandbox_workspace_write.network_access=false"]);
});

test("codex: never sandboxed", async () => {
  const { sandboxPolicyFor } = await import("./codex");
  for (const mode of ["manual", "acceptEdits", "plan", "auto"]) expect(sandboxPolicyFor({ codex: { sandbox: "workspace-write", spawnArgs: [] } } as any, { mode })).toEqual({ type: "dangerFullAccess" });
});
