/** Bun.spawn / spawnSync mặc định ẩn cửa sổ trên Windows: runner build không có console (--windows-hide-console),
 *  nên mỗi tiến trình con dạng console (codex, claude, agy, node, cmd, schtasks…) sẽ tự bật một cửa sổ đen nếu không ẩn.
 *  Chỗ nào cần hiện cửa sổ (mở cửa sổ dòng lệnh để đăng nhập) thì truyền windowsHide: false. Giữ nguyên kiểu của Bun. */
const hide = (a: any[]) => {
  if (Array.isArray(a[0])) a[1] = { windowsHide: true, ...(a[1] ?? {}) };
  else a[0] = { windowsHide: true, ...a[0] };
  return a;
};

export const spawn: typeof Bun.spawn = ((...a: any[]) => (Bun.spawn as any)(...hide(a))) as any;
export const spawnSync: typeof Bun.spawnSync = ((...a: any[]) => (Bun.spawnSync as any)(...hide(a))) as any;
