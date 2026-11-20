import { expect, test } from "bun:test";
import { mentionPrefix } from "./messages";

test("mention before a block reply goes on its own paragraph", () => {
  for (const m of ["```text\nTiêu đề: Re: …\n```", "# Báo cáo", "- một\n- hai", "1. bước một", "2) bước", "> trích", "| a | b |\n|---|---|", "  ```sh\nls\n```", "~~~\nx\n~~~"]) {
    expect(mentionPrefix("ba.flygo.vn", m)).toBe("@ba.flygo.vn\n\n");
  }
});

test("mention before plain text stays on the same line", () => {
  for (const m of ["Xong rồi ạ.", "#hashtag không phải tiêu đề", "-5 độ", "2026 là năm", "Dùng `code` nhé"]) {
    expect(mentionPrefix("ba", m)).toBe("@ba ");
  }
});
