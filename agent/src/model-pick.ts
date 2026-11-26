// session_new(model?, effort?) (2026-11-26): chọn model / mức suy nghĩ cho phiên mới theo cách người dùng gọi ("Sonnet 5.5",
// "sonnet", "claude-sonnet-5-5"…), chỉ trong danh sách model / mức bot dùng được (botOptions + model engine báo có).

export interface ModelInfo { id: string; name?: string }
const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "");

/** Model khớp [want] trong [models] (id dùng được) theo: id đúng → id / tên hiển thị bỏ dấu, hoa thường, dấu chấm, gạch →
 *  id chứa chuỗi (vd "sonnet" → "claude-sonnet-5-5"). Không khớp thì null. Nhiều model cùng chứa thì lấy model đứng trước. */
export function pickModel(want: string, models: string[], info: ModelInfo[] = []): string | null {
  const w = String(want ?? "").trim();
  if (!w) return null;
  if (models.includes(w)) return w;
  const n = norm(w);
  if (!n) return null;
  const named = new Map<string, string>();
  for (const m of info) if (m.name && models.includes(m.id)) named.set(norm(m.name), m.id);
  const exact = models.find((m) => norm(m) === n) ?? named.get(n);
  if (exact) return exact;
  return models.find((m) => norm(m).includes(n)) ?? [...named].find(([k]) => k.includes(n))?.[1] ?? null;
}

/** Mức suy nghĩ hợp lệ (không phân biệt hoa thường) hoặc null. */
export function pickEffort(want: string, efforts: string[]): string | null {
  const w = String(want ?? "").trim().toLowerCase();
  return w ? efforts.find((e) => e.toLowerCase() === w) ?? null : null;
}
