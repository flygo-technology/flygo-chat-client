import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { flygoAiEnv } from "./engines/claude";

const dir = mkdtempSync(join(tmpdir(), "fai-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

test("Cổng AI: env cho Claude Code mang khoá ứng dụng + email người nhờ", async () => {
  const keyFile = join(dir, "k");
  writeFileSync(keyFile, "fgk_abc123\n");
  const env = await flygoAiEnv({ serverUrl: "https://chat.flygo.vn", flygoAi: { url: "http://192.168.2.4:8807/", keyFile } }, "lan@flygo.vn");
  expect(env.ANTHROPIC_BASE_URL).toBe("http://192.168.2.4:8807");
  expect(env.ANTHROPIC_AUTH_TOKEN).toBe("fgk_abc123");
  expect(env.ANTHROPIC_API_KEY).toBe("");
  expect(env.ANTHROPIC_CUSTOM_HEADERS).toBe("X-Flygo-User: lan@flygo.vn\nX-Flygo-App: vn.flygo.agent");
  expect(env.ENABLE_TOOL_SEARCH).toBe("true");
  // Không đặt url: dùng đường công khai trên máy chủ chat.
  const pub = await flygoAiEnv({ serverUrl: "https://chat.flygo.vn/", flygoAi: { keyFile } }, "lan@flygo.vn");
  expect(pub.ANTHROPIC_BASE_URL).toBe("https://chat.flygo.vn/__apps/ai");
});

test("Cổng AI: thiếu khoá hoặc không biết người nhờ thì không chạy", async () => {
  await expect(flygoAiEnv({ serverUrl: "https://x", flygoAi: { url: "http://x", keyFile: join(dir, "none") } }, "lan@flygo.vn")).rejects.toThrow("khoá ứng dụng");
  const keyFile = join(dir, "k2");
  writeFileSync(keyFile, "fgk_x");
  await expect(flygoAiEnv({ serverUrl: "https://x", flygoAi: { url: "http://x", keyFile } }, "")).rejects.toThrow("email người nhờ");
});
