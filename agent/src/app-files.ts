// Tệp cho tool app công ty (Gateway) mà không phải tự base64 / tự tải lên Drive (2026-11-26, góp ý từ phiên DND IoT):
//   - Mail mail_upload_attachment: nhận thêm `path` (tệp trên máy bot) hoặc `file_id` (tệp đính kèm trong chat). Runner đọc tệp,
//     kiểm giới hạn (10 MB / tệp; gửi qua Cloudflare cả thư tối đa 5 MB) rồi gọi app với content_base64.
//   - Office office_* (đọc / sửa Word, Excel, PowerPoint trong Drive): nhận thêm `local_path` / `file_id`. Runner chép tệp lên Drive
//     (thư mục "/Tệp từ AI", không ghi đè tệp có sẵn) rồi gọi tool với path trên Drive. Thay đổi nằm ở bản Drive; tệp trên máy giữ nguyên.
// Chỉ đọc tệp trong thư mục làm việc của lượt và projectRoots của bot (không mở rộng quyền đọc tệp), trừ thư mục khoá / token.
// Tool vẫn chạy dưới vé (quyền) của người giao việc như gọi thẳng.

import { createHash } from "node:crypto";
import { realpathSync, statSync } from "node:fs";
import { basename, sep } from "node:path";
import { absPath, forbidden } from "./fs-tools";

export const MAIL_FILE_MAX = 10 * 1024 * 1024;
export const MAIL_CF_TOTAL = 5 * 1024 * 1024;
export const OFFICE_FILE_MAX = 50 * 1024 * 1024; // drive_write_file nhận tối đa 50 MB
export const AI_DRIVE_FOLDER = "/Tệp từ AI";
const DRIVE_WRITE = "vn_flygo_web_drive__drive_write_file";

export const isMailUpload = (name: string) => /^vn_flygo_[a-z0-9_]*mail__mail_upload_attachment$/.test(name);
export const isOfficeTool = (name: string, schema?: any) => /^vn_flygo_[a-z0-9_]*office__office_/.test(name) && !!schema?.properties?.path;

export interface LoadedFile { name: string; bytes: Uint8Array; mime?: string; key: string; from: string }

const mb = (n: number) => `${(n / 1024 / 1024).toFixed(n < 1024 * 1024 ? 2 : 1)} MB`;

/** Thêm tham số path / file_id vào schema tool app (danh sách tool agent thấy). Không đổi schema thì trả nguyên. */
export function augmentSchema(name: string, schema: any): any {
  if (!schema || typeof schema !== "object") return schema;
  const props = schema.properties ?? {};
  if (isMailUpload(name)) {
    return {
      ...schema,
      properties: {
        ...props,
        path: { type: "string", description: "Hoặc: đường dẫn tệp trên máy bot (trong thư mục làm việc / thư mục dự án), vd attachments/bao-cao.pdf. Runner tự đọc và chuyển base64." },
        file_id: { type: "string", description: "Hoặc: id tệp đính kèm trong chat (file_id từ chat_files / chat_get_files)." },
      },
      required: (schema.required ?? []).filter((k: string) => k !== "content_base64" && k !== "name"),
    };
  }
  if (isOfficeTool(name, schema)) {
    return {
      ...schema,
      properties: {
        ...props,
        local_path: { type: "string", description: "Hoặc: tệp .docx / .xlsx / .pptx trên máy bot (thư mục làm việc / dự án). Runner chép lên Drive (\"/Tệp từ AI\") rồi làm trên bản đó; sửa xong tệp trên máy không đổi." },
        file_id: { type: "string", description: "Hoặc: id tệp Office đính kèm trong chat (chép lên Drive như local_path)." },
      },
    };
  }
  return schema;
}

/** Mô tả tool kèm cách dùng mới (để agent biết không phải tự base64). */
export function augmentDescription(name: string, desc: string | undefined, schema?: any): string | undefined {
  if (isMailUpload(name)) return `${desc ?? ""} Đưa tệp bằng MỘT trong: path (tệp trên máy bot), file_id (tệp trong chat) hoặc content_base64. Tệp trong Drive: chưa đính kèm thẳng được, gửi link (drive_share) hoặc tải về máy trước.`.trim();
  if (isOfficeTool(name, schema)) return `${desc ?? ""} Tệp trên máy bot / trong chat: đưa local_path hoặc file_id thay cho path.`.trim();
  return desc;
}

/** Đường dẫn tệp trên máy được phép đọc cho tool app: chỉ trong [roots] (thư mục làm việc, projectRoots), không phải khoá / token. */
export function resolveLocal(p: string, roots: string[], cwd: string): string {
  const abs = absPath(p, cwd);
  let real: string;
  try { real = realpathSync(abs); } catch { throw new Error(`không thấy tệp ${p}`); }
  if (forbidden(real)) throw new Error(`không được đọc ${p} (khoá / token của máy)`);
  const ok = roots.some((r) => { try { const rr = realpathSync(r); return real === rr || real.startsWith(rr.endsWith(sep) ? rr : rr + sep); } catch { return false; } });
  if (!ok) throw new Error(`${p} nằm ngoài thư mục làm việc / thư mục dự án của bot; chép tệp vào thư mục làm việc trước (file_copy)`);
  if (!statSync(real).isFile()) throw new Error(`${p} không phải tệp`);
  return real;
}

export async function readLocal(p: string, roots: string[], cwd: string, max: number): Promise<LoadedFile> {
  const real = resolveLocal(p, roots, cwd);
  const size = statSync(real).size;
  if (size > max) throw new Error(`tệp ${basename(real)} ${mb(size)}, quá giới hạn ${mb(max)}`);
  const bytes = new Uint8Array(await Bun.file(real).arrayBuffer());
  return { name: basename(real), bytes, key: `local:${createHash("sha1").update(bytes).digest("hex")}`, from: p };
}

export interface PrepDeps {
  loadLocal(path: string, max: number): Promise<LoadedFile>;
  loadChat(fileId: string, max: number): Promise<LoadedFile>;
  /** Gọi tool Gateway (vé của lượt). */
  gateway(name: string, args: any): Promise<any>;
  /** Bản Drive đã chép của tệp (theo nội dung / file_id) trong phiên: gọi lần sau làm trên cùng bản, không chép lại. */
  driveCache: Map<string, string>;
}
export type Prepared = { args: any; note?: string } | { error: string };

/** Cần chép tệp lên Drive (Office với local_path / file_id): tool ghi, phải xin duyệt kể cả tool đọc. */
export function needsUpload(name: string, args: any, schema?: any): boolean {
  return isOfficeTool(name, schema) && !!(args?.local_path || args?.file_id);
}

function drivePathOf(r: any): string | undefined {
  if (r?.structuredContent?.path) return String(r.structuredContent.path);
  const t = r?.content?.find?.((c: any) => c?.type === "text")?.text;
  try { const j = JSON.parse(String(t ?? "")); return j?.path ? String(j.path) : undefined; } catch { return undefined; }
}

/** Đổi tham số path / file_id / local_path thành tham số app hiểu. Không có gì cần đổi thì trả nguyên. */
export async function prepareAppArgs(name: string, a: any, schema: any, d: PrepDeps): Promise<Prepared> {
  const args = { ...(a ?? {}) };
  if (isMailUpload(name)) {
    const { path, file_id, ...rest } = args;
    if (rest.content_base64) {
      if (!rest.name) return { error: "Thiếu name (tên tệp, có đuôi) khi đưa content_base64." };
      return { args: rest };
    }
    if (!path && !file_id) return { error: "Cần một trong: path (tệp trên máy bot), file_id (tệp trong chat) hoặc content_base64." };
    let f: LoadedFile;
    try { f = path ? await d.loadLocal(String(path), MAIL_FILE_MAX) : await d.loadChat(String(file_id), MAIL_FILE_MAX); }
    catch (e: any) { return { error: `Không đính kèm được: ${e?.message ?? e}. Thư nhận tối đa ${mb(MAIL_FILE_MAX)} / tệp.` }; }
    const out = { ...rest, name: rest.name || f.name, ...(rest.type || f.mime ? { type: rest.type || f.mime } : {}), content_base64: Buffer.from(f.bytes).toString("base64") };
    const note = f.bytes.length > MAIL_CF_TOTAL ? `Lưu ý: tệp ${mb(f.bytes.length)}; thư gửi qua Cloudflare chỉ nhận tối đa ${mb(MAIL_CF_TOTAL)} cả thư, có thể phải gửi link Drive thay cho đính kèm.` : undefined;
    return { args: out, ...(note ? { note } : {}) };
  }
  if (needsUpload(name, args, schema)) {
    const { local_path, file_id, ...rest } = args;
    delete rest.id;
    let f: LoadedFile;
    try { f = local_path ? await d.loadLocal(String(local_path), OFFICE_FILE_MAX) : await d.loadChat(String(file_id), OFFICE_FILE_MAX); }
    catch (e: any) { return { error: `Không mở được tệp: ${e?.message ?? e}` }; }
    let drive = d.driveCache.get(f.key);
    let note: string;
    if (drive) note = `Làm trên bản Drive đã chép trước đó: ${drive}.`;
    else {
      const r = await d.gateway(DRIVE_WRITE, { path: `${AI_DRIVE_FOLDER}/${f.name}`, base64: Buffer.from(f.bytes).toString("base64"), conflict: "rename" });
      if (r?.isError) return { error: `Không chép được tệp lên Drive: ${r.content?.[0]?.text ?? "lỗi"}` };
      drive = drivePathOf(r) ?? `${AI_DRIVE_FOLDER}/${f.name}`;
      d.driveCache.set(f.key, drive);
      note = `Tệp ${f.from} đã chép lên Drive: ${drive}.`;
    }
    return { args: { ...rest, path: drive }, note: `${note} Thay đổi nằm ở bản Drive (tệp gốc không đổi); gọi tiếp bằng path="${drive}".` };
  }
  return { args };
}

/** Gắn ghi chú vào kết quả MCP (đầu danh sách content). */
export function withNote(result: any, note?: string): any {
  if (!note || !result || typeof result !== "object") return result;
  return { ...result, content: [{ type: "text", text: note }, ...(Array.isArray(result.content) ? result.content : [])] };
}
