import { describe, expect, test } from "bun:test";
import { parseWhen } from "./chat-ops";
import {
  collectRange, normPost, orderPosts, pageEntries, parseAgySteps, parseClaudeJsonl, parseCodexRollout, pbDecode, rangeOf, redact,
  renderChatTranscript, renderEntry, renderExportJsonl, renderExportMd, type NPost,
} from "./history";

const P = (id: string, at: number, extra: Partial<NPost> = {}): NPost => ({ id, at, user_id: "u", user: "An", root_id: "", message: `m-${id}`, files: [], reactions: [], ...extra });

describe("collectRange", () => {
  // Máy chủ giả: tin 0..n-1 (tin i lúc i*1000), trang mới -> cũ, before = id tin cũ nhất trang trước.
  const server = (n: number, per: number, log: (string | undefined)[] = []) => async (before?: string) => {
    log.push(before);
    const all = Array.from({ length: n }, (_, i) => ({ id: `p${i}`, t: i * 1000 })).reverse();
    const start = before ? all.findIndex((p) => p.id === before) + 1 : 0;
    const posts = all.slice(start, start + per);
    return { posts: [...posts].sort(() => Math.random() - 0.5), more: posts.length === per }; // thứ tự trong trang bất kỳ
  };
  test("gộp các trang, bỏ trùng, sắp cũ -> mới, dừng khi qua from", async () => {
    const calls: (string | undefined)[] = [];
    const r = await collectRange(server(1000, 100, calls), { from: 850_000, to: Infinity, at: (p) => p.t, maxPosts: 10_000, maxScan: 10_000 });
    expect(r.posts.map((p) => p.id)).toEqual(Array.from({ length: 150 }, (_, i) => `p${850 + i}`));
    expect(r.complete).toBe(true);
    expect(calls).toEqual([undefined, "p900"]); // trang 2 đã có tin cũ hơn from -> dừng
  });
  test("lọc to, trang trùng tin (máy chủ trả lại tin cũ) không lặp vô hạn", async () => {
    let n = 0;
    const dup = async () => ({ posts: [{ id: "a", t: 5 }, { id: "b", t: 4 }], more: ++n < 50 });
    const r = await collectRange(dup, { from: 0, to: 4, at: (p) => p.t, maxPosts: 100, maxScan: 100 });
    expect(r.posts.map((p) => p.id)).toEqual(["b"]);
    expect(n).toBe(2);
  });
  test("trần max_posts giữ phần mới nhất; stopAt dừng sớm; max_scan", async () => {
    const a = await collectRange(server(1000, 100), { from: 0, to: Infinity, at: (p) => p.t, maxPosts: 250, maxScan: 10_000 });
    expect(a.complete).toBe(false);
    expect(a.reason).toBe("max_posts");
    expect(a.posts.length).toBe(250);
    expect(a.posts[0].id).toBe("p750");
    expect(a.posts.at(-1)!.id).toBe("p999");
    const b = await collectRange(server(1000, 100), { from: 0, to: 500_000, at: (p) => p.t, maxPosts: 10_000, maxScan: 10_000, stopAt: 5 });
    expect(b.reason).toBe("enough");
    expect(b.posts.at(-1)!.id).toBe("p500");
    const c = await collectRange(server(1000, 100), { from: 0, to: Infinity, at: (p) => p.t, maxPosts: 10_000, maxScan: 300 });
    expect(c.reason).toBe("max_scan");
    expect(c.scanned).toBe(300);
  });
});

describe("rangeOf", () => {
  test("ngày trơn ở to = hết ngày (giờ Việt Nam), lỗi rõ ràng", () => {
    const r = rangeOf("2026-11-01", "2026-11-01", parseWhen);
    expect(r.from).toBe(Date.parse("2026-11-01T00:00:00+07:00"));
    expect(r.to).toBe(Date.parse("2026-11-02T00:00:00+07:00") - 1);
    expect(rangeOf(undefined, undefined, parseWhen)).toEqual({ from: 0, to: Infinity });
    expect(rangeOf("2026-11-03", "2026-11-01", parseWhen).err).toContain("from sau to");
    expect(rangeOf("abc", "", parseWhen).err).toContain("không hợp lệ");
    expect(rangeOf(1793760000000, "", parseWhen).from).toBe(1793760000000);
  });
});

describe("redact", () => {
  test("che token / khoá / mật khẩu, giữ chữ thường", () => {
    const s = [
      "OPENAI=sk-proj-abcdefghijklmnopqrstuvwxyz123456",
      "Authorization: Bearer abcdefghijklmnop1234567890",
      'MM_TOKEN=k1uux8po4fy13nuqa37wuqwgga', '{"password":"hunter2hunter2"}', "api_key: AIzaSyA1234567890abcdefghijklmnopqrstuv",
      "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "postgres://admin:SuperSecret9@db:5432/x", "bot 1234567890:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ",
      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
      "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\n-----END OPENSSH PRIVATE KEY-----", "curl --token abcdef123456 x",
      "input_tokens: 22385, max_tokens: 1000, token: true", "Sếp gửi tin lúc 08:00",
    ].join("\n");
    const r = redact(s);
    for (const leak of ["abcdefghijklmnopqrstuvwxyz123456", "abcdefghijklmnop1234567890", "k1uux8po4fy13nuqa37wuqwgga", "hunter2hunter2", "AIzaSyA1234567890",
      "ghp_abcdef", "SuperSecret9", "AAHdqTcvCH1vGWJ", "dozjgNryP4J3", "b3BlbnNzaC1rZXk", "abcdef123456"]) expect(r).not.toContain(leak);
    expect(r).toContain("MM_TOKEN=[đã ẩn]");
    expect(r).toContain("postgres://admin:[đã ẩn]@db:5432/x");
    expect(r).toContain("input_tokens: 22385, max_tokens: 1000, token: true");
    expect(r).toContain("Sếp gửi tin lúc 08:00");
  });
});

describe("xuất lịch sử", () => {
  const posts = [
    P("r1", Date.parse("2026-11-01T09:00:00+07:00"), { reply_count: 2 }),
    P("x1", Date.parse("2026-11-01T09:05:00+07:00"), { root_id: "old", message: "trả lời luồng cũ" }),
    P("a1", Date.parse("2026-11-01T10:00:00+07:00"), { root_id: "r1", files: [{ id: "f1", name: "a.pdf", size: 3 }], reactions: [{ emoji: "+1", users: ["Bình"] }] }),
    P("m2", Date.parse("2026-11-02T08:00:00+07:00"), { edit_at: Date.parse("2026-11-02T08:01:00+07:00"), message: "dòng 1\ndòng 2" }),
    P("a2", Date.parse("2026-11-02T09:00:00+07:00"), { root_id: "r1" }),
  ];
  test("nested gom trả lời dưới tin gốc, ghi luồng cũ ngoài khoảng; none bỏ trả lời", () => {
    expect(orderPosts(posts, "nested").map((x) => `${x.p.id}:${x.depth}`)).toEqual(["r1:0", "a1:1", "a2:1", "x1:1", "m2:0"]);
    expect(orderPosts(posts, "none").map((x) => x.p.id)).toEqual(["r1", "m2"]);
    const md = renderExportMd("# T", posts, "nested");
    expect(md).toContain("(trả lời trong luồng #old, tin gốc trước khoảng thời gian này)");
    expect(md).toContain("    - tệp: a.pdf (file_id=f1, 3B)");
    expect(md).toContain("cảm xúc: :+1: Bình");
    expect(md).toContain("dòng 1\n  dòng 2");
    expect(md.match(/^## 2026-11-0\d$/gm)).toEqual(["## 2026-11-01", "## 2026-11-02"]);
    const inline = renderExportMd("# T", posts, "inline");
    expect(inline).toContain("trả lời luồng #r1");
    const jl = renderExportJsonl(posts, "inline").trim().split("\n").map((l) => JSON.parse(l));
    expect(jl.map((x) => x.id)).toEqual(["r1", "x1", "a1", "m2", "a2"]);
    expect(jl[3].edited_at).toBe("2026-11-02T01:01:00.000Z");
  });
  test("normPost: tên người, cảm xúc gom theo emoji, file_ids khi thiếu metadata", () => {
    const names = new Map([["u1", "An"], ["u2", "Bình"]]);
    const n = normPost({ id: "p", create_at: 1, user_id: "u1", message: "x", root_id: "", file_ids: ["f9"], metadata: { reactions: [{ user_id: "u1", emoji_name: "heart" }, { user_id: "u2", emoji_name: "heart" }] } }, names);
    expect(n.user).toBe("An");
    expect(n.reactions).toEqual([{ emoji: "heart", users: ["An", "Bình"] }]);
    expect(n.files).toEqual([{ id: "f9", name: "(tệp)" }]);
  });
});

describe("bản ghi engine", () => {
  test("Claude Code jsonl: lời người dùng, chữ trợ lý, tool_use, tool_result, compact; bỏ isMeta / thinking", () => {
    const lines = [
      { type: "user", timestamp: "2026-11-04T01:00:00Z", message: { role: "user", content: "Sửa lỗi đăng nhập" } },
      { type: "user", isMeta: true, timestamp: "2026-11-04T01:00:00Z", message: { content: "<local-command-caveat>" } },
      { type: "assistant", timestamp: "2026-11-04T01:00:05Z", message: { content: [{ type: "thinking", thinking: "bí mật" }, { type: "text", text: "Em xem file." }, { type: "tool_use", name: "Read", input: { file_path: "/a.ts" } }] } },
      { type: "user", timestamp: "2026-11-04T01:00:06Z", message: { content: [{ type: "tool_result", content: [{ type: "text", text: "nội dung tệp" }] }] } },
      { type: "user", timestamp: "2026-11-04T01:00:07Z", message: { content: [{ type: "tool_result", is_error: true, content: "ENOENT" }] } },
      { type: "system", subtype: "compact_boundary", timestamp: "2026-11-04T01:01:00Z" },
      "không phải json",
    ].map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join("\n");
    const e = parseClaudeJsonl(lines);
    expect(e.map((x) => x.role)).toEqual(["user", "assistant", "tool", "result", "error", "system"]);
    expect(e[2].text).toBe('Read({"file_path":"/a.ts"})');
    expect(e[3].text).toBe("nội dung tệp");
    expect(e[0].at).toBe(Date.parse("2026-11-04T01:00:00Z"));
    expect(JSON.stringify(e)).not.toContain("bí mật");
  });
  test("Codex rollout: bỏ developer, AGENTS.md thành hệ thống, function/custom call + output, lỗi lượt", () => {
    const lines = [
      { timestamp: "2026-11-04T02:23:52Z", type: "session_meta", payload: { id: "t1" } },
      { timestamp: "2026-11-04T02:23:55Z", type: "response_item", payload: { type: "message", role: "developer", content: [{ type: "input_text", text: "persona" }] } },
      { timestamp: "2026-11-04T02:23:55Z", type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "# AGENTS.md instructions for /x\n<INSTRUCTIONS>…" }] } },
      { timestamp: "2026-11-04T02:23:56Z", type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "Đọc bàn giao" }] } },
      { timestamp: "2026-11-04T02:23:59Z", type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Em đọc." }] } },
      { timestamp: "2026-11-04T02:24:00Z", type: "response_item", payload: { type: "custom_tool_call", name: "exec", input: "cat a.md", call_id: "c1" } },
      { timestamp: "2026-11-04T02:24:00Z", type: "response_item", payload: { type: "custom_tool_call_output", call_id: "c1", output: [{ type: "input_text", text: "Output: ok" }] } },
      { timestamp: "2026-11-04T02:24:01Z", type: "response_item", payload: { type: "function_call", name: "shell", arguments: "{\"cmd\":\"ls\"}" } },
      { timestamp: "2026-11-04T02:24:01Z", type: "response_item", payload: { type: "function_call_output", output: "a.md" } },
      { timestamp: "2026-11-04T02:24:02Z", type: "response_item", payload: { type: "reasoning", summary: [], encrypted_content: "gAAA" } },
      { timestamp: "2026-11-04T02:24:03Z", type: "event_msg", payload: { type: "token_count" } },
      { timestamp: "2026-11-04T02:24:04Z", type: "compacted", payload: { message: "" } },
      { timestamp: "2026-11-04T02:24:05Z", type: "event_msg", payload: { type: "task_complete", error: { message: "usage limit" } } },
    ].map((x) => JSON.stringify(x)).join("\n");
    const e = parseCodexRollout(lines);
    expect(e.map((x) => x.role)).toEqual(["system", "user", "assistant", "tool", "result", "tool", "result", "system", "error"]);
    expect(e[3].text).toBe("exec(cat a.md)");
    expect(e[4].text).toBe("Output: ok");
    expect(e[5].text).toBe('shell({"cmd":"ls"})');
    expect(e[8].text).toBe("usage limit");
  });

  // protobuf tối giản để dựng bước Antigravity giả
  const enc = new TextEncoder();
  const vint = (n: number) => { const o: number[] = []; while (n > 127) { o.push((n % 128) | 128); n = Math.floor(n / 128); } o.push(n); return o; };
  const fld = (f: number, v: string | number | Uint8Array): Uint8Array => {
    if (typeof v === "number") return new Uint8Array([...vint(f * 8), ...vint(v)]);
    const b = typeof v === "string" ? enc.encode(v) : v;
    return new Uint8Array([...vint(f * 8 + 2), ...vint(b.length), ...b]);
  };
  const msg = (...parts: Uint8Array[]) => { const n = parts.reduce((s, p) => s + p.length, 0); const o = new Uint8Array(n); let i = 0; for (const p of parts) { o.set(p, i); i += p.length; } return o; };
  const meta = (sec: number) => fld(5, msg(fld(1, msg(fld(1, sec), fld(2, 5))), fld(12, "e48d3258-a118-4e00-8239-2263e2c97c78")));
  test("Antigravity: giải protobuf không schema, dựng lượt người dùng / trợ lý / tool / kết quả / lỗi", () => {
    const sec = 1793622609;
    const rows = [
      { idx: 0, step_type: 14, step_payload: msg(fld(1, 14), meta(sec), fld(19, msg(fld(2, "Kiểm tra TV giúp em"), fld(12, "915b76fd-40cf-40fd-9b9a-6f3dfe9bf2af")))) },
      { idx: 1, step_type: 15, step_payload: msg(fld(1, 15), meta(sec + 2), fld(20, msg(fld(1, "Em SSH vào kiểm tra."), fld(3, "The user wants (thinking)"),
        fld(7, msg(fld(1, "toolu_vrtx_01abc"), fld(2, "run_command"), fld(3, "{\"CommandLine\":\"ssh tv \\u0026\\u0026 ls\"}")))))) },
      { idx: 2, step_type: 132, step_payload: msg(fld(1, 132), meta(sec + 3), fld(140, msg(fld(1, msg(fld(1, "CommandLine"), fld(2, "ssh tv"))), fld(2, msg(fld(1, "Command exited with code 0.\nok"), fld(7, "file:///x/output.txt")))))) },
      { idx: 3, step_type: 17, step_payload: msg(fld(1, 17), meta(sec + 4), fld(30, msg(fld(1, "Individual quota reached."), fld(2, "RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 2h")))) },
      { idx: 4, step_type: 99, step_payload: msg(fld(1, 99)) },
      { idx: 5, step_type: 15, step_payload: null },
    ];
    const e = parseAgySteps(rows as any);
    expect(e.map((x) => x.role)).toEqual(["user", "assistant", "tool", "result", "error"]);
    expect(e[0].text).toBe("Kiểm tra TV giúp em");
    expect(e[0].at).toBe(sec * 1000);
    expect(e[1].text).toBe("Em SSH vào kiểm tra.");
    expect(e[2].text).toBe('run_command({"CommandLine":"ssh tv && ls"})');
    expect(e[3].text).toBe("Command exited with code 0.\nok");
    expect(e[4].text).toBe("Individual quota reached.");
    expect(JSON.stringify(e)).not.toContain("thinking");
    expect(pbDecode(new Uint8Array([0x0a, 0xff]))).toBeNull(); // độ dài vượt bộ đệm
  });
});

describe("bản ghi Flygo Chat + phân trang", () => {
  test("kênh phiên AI: người dùng, thẻ bước xen chữ theo seg, bỏ tin trùng câu trả lời cuối / đang stream", () => {
    const BOT = "bot";
    const posts = [
      { id: "1", create_at: 1000, user_id: "sep", message: "Làm báo cáo", metadata: { files: [{ name: "so-lieu.xlsx" }] } },
      { id: "2", create_at: 2000, user_id: BOT, message: "fallback", props: { flygo_agent: { status: "done", texts: ["Em đọc số liệu.", "Xong rồi Sếp."], steps: [{ label: "Đọc so-lieu.xlsx", status: "done", seg: 1 }, { label: "Chạy script", status: "error", detail: "exit 1", seg: 1 }] } } },
      { id: "3", create_at: 2100, user_id: BOT, message: "Xong rồi Sếp." },
      { id: "4", create_at: 2200, user_id: BOT, message: "đang viết", props: { flygo_agent_message: { streaming: true } } },
      { id: "5", create_at: 2300, user_id: BOT, message: "", type: "system_add_to_channel" },
      { id: "6", create_at: 3000, user_id: BOT, message: "Lỗi", props: { flygo_agent: { status: "error", error: "quá giờ", steps: [] } } },
    ];
    const e = renderChatTranscript(posts, BOT, new Map([["sep", "Sếp Ba"]]));
    expect(e.map((x) => x.role)).toEqual(["user", "assistant", "tool", "assistant", "error"]);
    expect(e[0].text).toBe("Sếp Ba: Làm báo cáo\n[tệp: so-lieu.xlsx]");
    expect(e[2].text).toBe("2 bước: ✓ Đọc so-lieu.xlsx · ✗ Chạy script — exit 1");
    expect(e[4].text).toBe("quá giờ");
  });
  test("pageEntries: last lấy đuôi vừa max_chars, all đi xuôi từ from_entry; renderEntry che bí mật", () => {
    const es = Array.from({ length: 50 }, (_, i) => ({ role: (i % 2 ? "assistant" : "user") as any, text: `mục ${i} ${"x".repeat(80)}` }));
    const last = pageEntries(es, { part: "last", maxChars: 1000 });
    expect(last.last).toBe(49);
    expect(last.first).toBeGreaterThan(30);
    expect(last.text.length).toBeLessThanOrEqual(1000);
    const prev = pageEntries(es, { part: "last", maxChars: 1000, beforeEntry: last.first });
    expect(prev.last).toBe(last.first - 1);
    const all = pageEntries(es, { part: "all", maxChars: 1000, fromEntry: 10 });
    expect(all.first).toBe(10);
    expect(all.text.startsWith("[10] Người dùng: mục 10")).toBe(true);
    expect(pageEntries([], { part: "last", maxChars: 1000 }).text).toBe("");
    expect(renderEntry({ role: "result", text: "TOKEN=abcdef1234567890" }, 0)).toBe("[0] Kết quả: TOKEN=[đã ẩn]");
    expect(renderEntry({ role: "tool", text: "y".repeat(700) }, 1).length).toBeLessThan(700);
  });
});
