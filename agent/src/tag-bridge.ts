// Cầu nối bot ↔ bot do người dùng mở trong một tin (0.6.95, luật của Sếp): cùng dự án thì bot luôn gọi nhau qua team_*;
// khác dự án / chat / app chỉ nhờ được bot được @tag trong tin đang xử lý, hoặc phiên được gắn vào tin (props.flygo_a2a_peers).
// Relay kiểm lại tin tag bằng token quản trị (x-flygo.tag_post), runner cũ không vượt qua được.

export interface TagBridge { post: string; bots: Set<string>; sessions: { bot: string; session: string }[] }

/** Phiên được gắn vào tin: [{bot, session}] (mỗi phiên hai dòng: theo bot_id và theo username). */
export function attachedSessions(props: any): { bot: string; session: string }[] {
  let ps: any = props?.flygo_a2a_peers;
  if (typeof ps === "string") try { ps = JSON.parse(ps); } catch { ps = null; }
  return (Array.isArray(ps) ? ps : []).filter((p: any) => p?.session_id && (p.bot_id || p.username))
    .flatMap((p: any) => [p.bot_id, p.username].filter(Boolean).map((b: any) => ({ bot: String(b), session: String(p.session_id) })));
}

/** Cầu nối của tin `postId` do người (không phải bot) gửi: bot được tag (trừ chính mình) + phiên được gắn. */
export function tagBridge(postId: string, tagged: { id: string; username: string }[], props: any, self: { id: string; username: string }): TagBridge | undefined {
  if (!postId) return undefined;
  const bots = new Set<string>();
  for (const t of tagged) if (t.id !== self.id) { bots.add(t.id); bots.add(t.username); }
  const sessions = attachedSessions(props);
  for (const x of sessions) if (x.bot !== self.id && x.bot !== self.username) bots.add(x.bot);
  return bots.size || sessions.length ? { post: postId, bots, sessions } : undefined;
}

/** Lý do không cho ask_agent tới bot `u` (phiên `session`), hoặc "" nếu được. */
export function tagDenied(t: TagBridge | undefined, u: { id: string; username: string }, session: string): string {
  const hint = "Chỉ nhờ được agent được tag trong tin đang xử lý (hoặc phiên được gắn vào tin); đồng đội cùng dự án thì dùng team_ask / team_post.";
  if (!t) return `Lượt này không có tin tag agent nào nên không nhờ @${u.username} được. ${hint}`;
  if (session) return t.sessions.some((x) => x.session === session && (x.bot === u.id || x.bot === u.username)) ? "" : `Phiên ${session} không được gắn vào tin này. ${hint}`;
  return t.bots.has(u.id) || t.bots.has(u.username) ? "" : `@${u.username} không được tag trong tin này. ${hint}`;
}

/** Tin máy đăng thay người (webhook, agent ngoài qua cầu nối MCP, tin hệ thống): không mở cầu nối dù tài khoản đăng là người. */
export function machinePost(post: { type?: string; props?: any }): boolean {
  const p = post?.props ?? {};
  return String(p.from_webhook) === "true" || String(p.from_bot) === "true" || !!p.flygo_bridge || String(post?.type ?? "").startsWith("system_");
}
