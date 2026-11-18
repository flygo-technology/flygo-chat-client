// Chế độ quyền của một lượt (Sếp 2026-11-18: "mở phiên chat mới mà vẫn phải bấm cho phép, mặc định luôn cho phép khi chạy
// chế độ full quyền"). App chỉ gửi props.flygo_agent_config["<bot>"].mode từ ô soạn tin chat; phiên mới ở Dự án AI, khung bên,
// lượt chạy lại… không có. Runner nhớ chế độ chủ bot chọn gần nhất và dùng cho mọi phiên của bot.
//  - Chỉ chủ bot: người khác không bao giờ được bypassPermissions (kể cả chế độ đã nhớ).
//  - "bật lại duyệt" trong một chat / luồng: phạm vi đó luôn duyệt tay dù chế độ chung là toàn quyền.
export type ResolveIn<M extends string> = {
  want?: unknown; // chế độ app gửi kèm tin (có thể thiếu)
  owner: boolean; // người gửi là chủ bot
  remembered?: string | null; // chế độ chủ bot chọn gần nhất (runner lưu)
  forcedManual: boolean; // phạm vi này đã "bật lại duyệt"
  modes: readonly M[];
  canBypass: boolean; // engine hỗ trợ bypassPermissions (không phải codex)
};
export type ResolveOut<M extends string> = { mode?: M; remember?: M; bad?: string };

export function resolvePermMode<M extends string>(i: ResolveIn<M>): ResolveOut<M> {
  const ok = (m: unknown): m is M => typeof m === "string" && (i.modes as readonly string[]).includes(m) && (m !== "bypassPermissions" || (i.canBypass && i.owner));
  const explicit = i.want != null && i.want !== "" ? i.want : undefined;
  if (explicit !== undefined && !ok(explicit)) return { bad: `chế độ ${explicit}` };
  // Chủ bot chọn rõ: nhớ lại cho các phiên sau.
  const remember = explicit !== undefined && i.owner ? (explicit as M) : undefined;
  let mode = explicit as M | undefined;
  if (mode === undefined && i.owner && ok(i.remembered)) mode = i.remembered;
  if (mode === "bypassPermissions" && i.forcedManual) mode = undefined; // về mặc định (duyệt tay)
  return { mode, ...(remember ? { remember } : {}) };
}
