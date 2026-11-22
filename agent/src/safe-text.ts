// Chữ an toàn để lưu lên Mattermost (Postgres): bỏ NUL và ký tự điều khiển C0 (giữ \t \n \r), thay surrogate lẻ bằng U+FFFD.
// 2026-11-22: tin có "\u0000" lấy từ tệp hw_ctree.xml.html làm POST /posts lỗi 500 (pq 22P05), lượt kẹt "Brewing" mãi.
const CTRL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g;
const LONE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g;

const HAS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/; // không /g: test() không giữ lastIndex

export const cleanText = (s: string): string => (HAS.test(s) ? s.replace(CTRL, "").replace(LONE, "\uFFFD") : s);

/** Làm sạch mọi chuỗi (cả khoá) trong một giá trị JSON. */
export function cleanDeep<T>(v: T): T {
  if (typeof v === "string") return cleanText(v) as T;
  if (Array.isArray(v)) return v.map(cleanDeep) as T;
  if (v && typeof v === "object" && (v as any).constructor === Object) {
    const o: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v)) o[cleanText(k)] = cleanDeep(x);
    return o as T;
  }
  return v;
}

/** Bản rút gọn của tin để gửi lại khi máy chủ từ chối: cắt message và các chuỗi dài trong props. */
export function shrinkPost<T extends { message?: string; props?: Record<string, any> }>(p: T, maxMessage = 16_000, maxProp = 4_000): T {
  const cut = (s: string, n: number) => (s.length > n ? `${s.slice(0, n)}\n…(đã cắt bớt)` : s);
  const deep = (v: any): any => typeof v === "string" ? cut(v, maxProp) : Array.isArray(v) ? v.map(deep) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, deep(x)])) : v;
  return { ...p, ...(typeof p.message === "string" ? { message: cut(p.message, maxMessage) } : {}), ...(p.props ? { props: deep(p.props) } : {}) };
}
