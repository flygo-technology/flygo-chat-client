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

test("moveToEnd: post đang chạy được đăng lại ở cuối (sau thẻ câu hỏi), post cũ bị xoá, sửa tiếp vào post mới", async () => {
  const { InlineReply } = await import("./messages");
  const { RunCard } = await import("./card");
  const log: string[] = [];
  let n = 0;
  const mm: any = {
    createPost: async (p: any) => { const id = `p${++n}`; log.push(`create ${id} streaming=${p.props.flygo_agent_message.streaming}`); return { id }; },
    patchPost: async (id: string) => { log.push(`patch ${id}`); return { id }; },
    deletePost: async (id: string) => { log.push(`delete ${id}`); },
  };
  const where = { channel_id: "c", root_id: "" };
  const reply = new InlineReply(mm, where, "run1", "claude", { id: "u", username: "ba" }, false);
  reply.card = new RunCard(mm, where, "run1", "claude", "t", "u", () => reply.touch());
  expect(await reply.ensurePost()).toBe("p1");
  expect(await reply.moveToEnd()).toBe(true);
  expect(reply.id).toBe("p2");
  expect(log).toEqual(["create p1 streaming=true", "create p2 streaming=true", "delete p1"]);
  reply.update({ id: "m1", delta: "tiếp" });
  await new Promise((r) => setTimeout(r, 600));
  expect(log.at(-1)).toBe("patch p2");
});
