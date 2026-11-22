import { afterEach, expect, test } from "bun:test";
import { MM } from "./mm";

const orig = globalThis.fetch;
afterEach(() => { globalThis.fetch = orig; });

test("POST /posts: làm sạch NUL trước khi gửi; máy chủ từ chối thì gửi lại bản rút gọn một lần", async () => {
  const bodies: string[] = [];
  let n = 0;
  globalThis.fetch = (async (_u: any, init: any) => {
    bodies.push(String(init.body));
    n++;
    return n === 1 ? new Response("app.post.save.app_error", { status: 500 }) : new Response(JSON.stringify({ id: "p1" }), { status: 201 });
  }) as any;
  const mm = new MM("https://x", "t");
  const p = await mm.createPost({ channel_id: "c", message: "a\u0000b".padEnd(30_000, "x"), props: { flygo_run: { out: "\u0000y" } } } as any);
  expect(p.id).toBe("p1");
  expect(bodies.length).toBe(2);
  for (const b of bodies) expect(b).not.toContain("\\u0000");
  expect(JSON.parse(bodies[1]).message.length).toBeLessThan(17_000);
});

test("lỗi thật sau khi gửi lại: báo rõ cả hai lần", async () => {
  globalThis.fetch = (async () => new Response("nope", { status: 500 })) as any;
  const mm = new MM("https://x", "t");
  await expect(mm.patchPost("abc123", { message: "x" })).rejects.toThrow(/gửi lại bản rút gọn/);
});
