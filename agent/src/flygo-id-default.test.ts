import { expect, test } from "bun:test";
import { flygoIdOf } from "./config";

test("Flygo ID / Gateway: thiếu cấu hình thì suy từ máy chủ chat; có thì giữ; null thì tắt", () => {
  expect(flygoIdOf({ serverUrl: "https://chat.flygo.vn/" })).toEqual({ url: "https://chat.flygo.vn/flygo-id", gatewayUrl: "https://chat.flygo.vn/__apps/flygo-gateway/mcp" });
  const own = { url: "https://chat.flygo.vn/flygo-id", gatewayUrl: "http://192.168.2.4:18789/mcp" };
  expect(flygoIdOf({ serverUrl: "https://chat.flygo.vn", flygoId: own })).toBe(own);
  expect(flygoIdOf({ serverUrl: "https://chat.flygo.vn", flygoId: null })).toBeUndefined();
  expect(flygoIdOf({ serverUrl: "chat.flygo.vn" })).toBeUndefined();
});
