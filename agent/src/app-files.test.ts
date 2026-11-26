import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AI_DRIVE_FOLDER, MAIL_FILE_MAX, augmentSchema, needsUpload, prepareAppArgs, readLocal, resolveLocal, withNote, type LoadedFile, type PrepDeps } from "./app-files";

const MAIL = "vn_flygo_mail__mail_upload_attachment";
const DOC = "vn_flygo_web_office__office_doc_read";
const MAIL_SCHEMA = { type: "object", properties: { mailbox: { type: "string" }, name: { type: "string" }, content_base64: { type: "string" }, type: { type: "string" } }, required: ["name", "content_base64"], additionalProperties: false };
const DOC_SCHEMA = { type: "object", properties: { path: { type: "string" }, id: { type: "integer" }, markdown: { type: "boolean" } }, required: [], additionalProperties: false };

function setup() {
  const base = mkdtempSync(join(tmpdir(), "appfiles-"));
  const work = join(base, "work"), outside = join(base, "outside");
  mkdirSync(join(work, "attachments"), { recursive: true }); mkdirSync(outside);
  writeFileSync(join(work, "attachments", "bao-cao.pdf"), "PDF-DATA");
  writeFileSync(join(outside, "secret.txt"), "x");
  symlinkSync(join(outside, "secret.txt"), join(work, "link.txt"));
  return { work, outside };
}
function deps(over: Partial<PrepDeps> = {}) {
  const calls: { name: string; args: any }[] = [];
  const d: PrepDeps = {
    loadLocal: async (p) => ({ name: p.split("/").pop()!, bytes: new TextEncoder().encode("DOCX"), key: `local:${p}`, from: p }),
    loadChat: async (id) => ({ name: "hop-dong.docx", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", bytes: new TextEncoder().encode("CHAT"), key: `chat:${id}`, from: "hop-dong.docx" }),
    gateway: async (name, args) => { calls.push({ name, args }); return { content: [{ type: "text", text: JSON.stringify({ path: `${AI_DRIVE_FOLDER}/hop-dong (1).docx`, id: 9 }) }] }; },
    driveCache: new Map(), ...over,
  };
  return { d, calls };
}

describe("schema tool app", () => {
  test("Mail: thêm path / file_id, không còn bắt content_base64 / name", () => {
    const s = augmentSchema(MAIL, MAIL_SCHEMA);
    expect(Object.keys(s.properties)).toEqual(["mailbox", "name", "content_base64", "type", "path", "file_id"]);
    expect(s.required).toEqual([]);
    expect(MAIL_SCHEMA.required).toEqual(["name", "content_base64"]); // không sửa schema gốc
  });
  test("Office có path: thêm local_path / file_id; tool khác giữ nguyên", () => {
    expect(Object.keys(augmentSchema(DOC, DOC_SCHEMA).properties)).toContain("local_path");
    const other = { type: "object", properties: { q: { type: "string" } } };
    expect(augmentSchema("vn_flygo_web_office__office_list_files", other)).toBe(other);
    expect(augmentSchema("vn_flygo_web_drive__drive_list", DOC_SCHEMA)).toBe(DOC_SCHEMA);
  });
});

describe("đọc tệp trên máy", () => {
  test("chỉ trong thư mục được phép; symlink ra ngoài bị chặn", async () => {
    const { work, outside } = setup();
    expect(resolveLocal("attachments/bao-cao.pdf", [work], work)).toEndWith("/attachments/bao-cao.pdf");
    expect(() => resolveLocal(join(outside, "secret.txt"), [work], work)).toThrow(/ngoài thư mục làm việc/);
    expect(() => resolveLocal("link.txt", [work], work)).toThrow(/ngoài thư mục làm việc/);
    expect(() => resolveLocal("khong-co.pdf", [work], work)).toThrow(/không thấy tệp/);
    expect(() => resolveLocal("attachments", [work], work)).toThrow(/không phải tệp/);
    expect(resolveLocal(join(outside, "secret.txt"), [work, outside], work)).toEndWith("secret.txt"); // projectRoots
  });
  test("quá giới hạn thì báo cỡ tệp", async () => {
    const { work } = setup();
    expect((await readLocal("attachments/bao-cao.pdf", [work], work, MAIL_FILE_MAX)).bytes.length).toBe(8);
    await expect(readLocal("attachments/bao-cao.pdf", [work], work, 4)).rejects.toThrow(/quá giới hạn/);
  });
});

describe("Mail mail_upload_attachment", () => {
  test("path: runner đọc tệp, gửi content_base64, tên lấy theo tệp, bỏ path", async () => {
    const { d } = deps();
    const r: any = await prepareAppArgs(MAIL, { path: "attachments/bao-cao.pdf", mailbox: "a@cf.flygo.vn" }, MAIL_SCHEMA, d);
    expect(r.args).toEqual({ mailbox: "a@cf.flygo.vn", name: "bao-cao.pdf", content_base64: Buffer.from("DOCX").toString("base64") });
  });
  test("file_id trong chat: lấy cả kiểu MIME; name người gọi đặt thì giữ", async () => {
    const { d } = deps();
    const r: any = await prepareAppArgs(MAIL, { file_id: "f1", name: "HD.docx" }, MAIL_SCHEMA, d);
    expect(r.args.name).toBe("HD.docx");
    expect(r.args.type).toStartWith("application/vnd.openxml");
    expect(r.args.file_id).toBeUndefined();
  });
  test("content_base64 như cũ; thiếu nguồn / lỗi đọc thì báo rõ", async () => {
    const { d } = deps({ loadLocal: async () => { throw new Error("tệp x 12.0 MB, quá giới hạn 10 MB"); } });
    expect(((await prepareAppArgs(MAIL, { name: "a.txt", content_base64: "eA==" }, MAIL_SCHEMA, d)) as any).args).toEqual({ name: "a.txt", content_base64: "eA==" });
    expect(((await prepareAppArgs(MAIL, {}, MAIL_SCHEMA, d)) as any).error).toContain("path");
    expect(((await prepareAppArgs(MAIL, { path: "x" }, MAIL_SCHEMA, d)) as any).error).toContain("quá giới hạn");
  });
  test("trên 5 MB: nhắc giới hạn Cloudflare", async () => {
    const big = new Uint8Array(6 * 1024 * 1024);
    const { d } = deps({ loadLocal: async (p): Promise<LoadedFile> => ({ name: "v.mp4", bytes: big, key: "k", from: p }) });
    expect(((await prepareAppArgs(MAIL, { path: "v.mp4" }, MAIL_SCHEMA, d)) as any).note).toContain("Cloudflare");
  });
});

describe("Office với tệp trên máy / trong chat", () => {
  test("chép lên Drive (không ghi đè), gọi tool bằng path Drive; lần sau dùng lại bản đã chép", async () => {
    const { d, calls } = deps();
    expect(needsUpload(DOC, { file_id: "f1" }, DOC_SCHEMA)).toBe(true);
    expect(needsUpload(DOC, { path: "/a.docx" }, DOC_SCHEMA)).toBe(false);
    const r: any = await prepareAppArgs(DOC, { file_id: "f1", markdown: true, id: 3 }, DOC_SCHEMA, d);
    expect(calls).toHaveLength(1);
    expect(calls[0].name).toBe("vn_flygo_web_drive__drive_write_file");
    expect(calls[0].args).toMatchObject({ path: `${AI_DRIVE_FOLDER}/hop-dong.docx`, conflict: "rename" });
    expect(r.args).toEqual({ markdown: true, path: `${AI_DRIVE_FOLDER}/hop-dong (1).docx` });
    expect(r.note).toContain("tệp gốc không đổi");
    const again: any = await prepareAppArgs(DOC, { file_id: "f1" }, DOC_SCHEMA, d);
    expect(calls).toHaveLength(1);
    expect(again.args.path).toBe(`${AI_DRIVE_FOLDER}/hop-dong (1).docx`);
  });
  test("Drive lỗi thì báo, không gọi tool Office", async () => {
    const { d } = deps({ gateway: async () => ({ isError: true, content: [{ type: "text", text: "Không có quyền dùng tool drive_write_file" }] }) });
    expect(((await prepareAppArgs(DOC, { local_path: "a.docx" }, DOC_SCHEMA, d)) as any).error).toContain("Không có quyền");
  });
  test("không có tham số mới thì giữ nguyên; ghi chú đứng đầu kết quả", async () => {
    const { d, calls } = deps();
    expect(((await prepareAppArgs(DOC, { path: "/a.docx" }, DOC_SCHEMA, d)) as any).args).toEqual({ path: "/a.docx" });
    expect(calls).toHaveLength(0);
    expect(withNote({ content: [{ type: "text", text: "ok" }] }, "n").content.map((c: any) => c.text)).toEqual(["n", "ok"]);
    const res = { content: [] };
    expect(withNote(res, undefined)).toBe(res);
  });
});
