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

test("splitHere: tin chèn của người -> post đang chạy giữ chỗ (chốt đoạn, run_id riêng), phần sau là post mới chỉ có chữ / bước mới", async () => {
  const { InlineReply } = await import("./messages");
  const { RunCard } = await import("./card");
  const created: any[] = [], patched: [string, any][] = [], deleted: string[] = [];
  let n = 0;
  const mm: any = {
    createPost: async (p: any) => { const id = `p${++n}`; created.push({ id, ...p }); return { id }; },
    patchPost: async (id: string, b: any) => { patched.push([id, b]); return { id }; },
    deletePost: async (id: string) => { deleted.push(id); },
  };
  const where = { channel_id: "c", root_id: "" };
  const reply = new InlineReply(mm, where, "run1", "claude", { id: "u", username: "ba" }, false);
  const card = new RunCard(mm, where, "run1", "claude", "t", "u", () => reply.touch());
  reply.card = card;
  reply.update({ id: "m1", delta: "Đang làm phần A" });
  card.step({ id: "s1", kind: "command", title: "ls", status: "done" });
  card.setTodos([{ text: "A", status: "in_progress" } as any]);
  await reply.ensurePost();
  expect(await reply.splitHere()).toBe(true);
  expect(reply.id).toBe("p2");
  expect(deleted).toEqual([]); // post cũ không bị xoá
  const [oldId, frozen] = patched.at(-1)!;
  expect(oldId).toBe("p1");
  expect(frozen.props.flygo_agent.status).toBe("continued");
  expect(frozen.props.flygo_agent.todos).toBeUndefined();
  expect(frozen.props.flygo_agent_message.run_id).toBe("run1~1");
  expect(frozen.props.flygo_agent_message.streaming).toBe(false);
  expect(frozen.message).toBe("Đang làm phần A");
  // Post mới: chưa có chữ / bước cũ, kế hoạch đi theo.
  const fresh = created.at(-1).props.flygo_agent;
  expect(fresh.texts).toEqual([]);
  expect(fresh.steps).toEqual([]);
  expect(fresh.todos.length).toBe(1);
  expect(created.at(-1).props.flygo_agent_message.run_id).toBe("run1");
  reply.update({ id: "m2", delta: "Phần B" });
  card.step({ id: "s2", kind: "command", title: "pwd", status: "done" });
  await new Promise((r) => setTimeout(r, 900));
  const last = patched.at(-1)!;
  expect(last[0]).toBe("p2");
  expect(last[1].message).toBe("Phần B");
  expect(last[1].props.flygo_agent.texts).toEqual(["Phần B"]);
  expect(last[1].props.flygo_agent.steps.map((s: any) => s.id)).toEqual(["s2"]);
  expect(last[1].props.flygo_agent.steps[0].seg).toBe(1); // bước đến sau đoạn chữ "Phần B"
});
