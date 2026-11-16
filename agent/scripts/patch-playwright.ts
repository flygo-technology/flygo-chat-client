// playwright-core dùng bản `ws` đóng gói sẵn của nó; trên Bun bước upgrade WebSocket của bản đó treo (connectOverCDP hết giờ).
// Đổi sang `ws` thường (Bun có cài đặt riêng, chạy tốt). Chạy sau `bun install` (postinstall) và trước khi build.
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const file = require.resolve("playwright-core/lib/coreBundle.js");
const src = readFileSync(file, "utf8");
const out = src.replaceAll('require("./utilsBundle").ws', 'require("ws")');
if (out !== src) { writeFileSync(file, out); console.log(`patch-playwright: ${file}`); }
else if (!src.includes('require("ws")')) { console.error("patch-playwright: không thấy chỗ cần vá (playwright-core đổi bản?)"); process.exit(1); }
