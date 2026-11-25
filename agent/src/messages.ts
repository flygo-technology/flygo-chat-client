// Mỗi lượt của agent là MỘT post (chat chính hoặc trong luồng): thẻ tiến trình props.flygo_agent + chữ stream
// props.flygo_agent_message = { run_id, engine, seq, streaming, final? } + lời xin duyệt props.flygo_agent_approval.
// Kết thúc lượt: ĐĂNG LẠI thành post mới (máy chủ chat chỉ báo khi tạo post, không báo khi sửa), post stream bị xoá.
import type { RunCard, Segment } from "./card";
import type { MM } from "./mm";

/** Câu trả lời mở đầu bằng khối markdown (```, #, -, 1., >, |bảng): nếu "@tên " đứng trước trên cùng một dòng thì
 *  markdown không còn nhận ra khối (hiện thành "```text" và chữ thường). */
const BLOCK_START = /^\s*(```|~~~|#{1,6}\s|[-*+]\s|\d{1,9}[.)]\s|>|\|)/;

/** "@tên " trước câu trả lời cuối; câu trả lời mở đầu bằng khối thì tên nằm riêng một đoạn ("@tên\n\n"). */
export function mentionPrefix(username: string, message: string): string {
  return BLOCK_START.test(message) ? `@${username}\n\n` : `@${username} `;
}

/** Trả lời của một lượt: MỘT post duy nhất, ở chat chính (root_id rỗng) hoặc trong luồng (flygo_reply).
 *  Post mang cả thẻ tiến trình (props.flygo_agent) lẫn tin stream (props.flygo_agent_message); chưa có chữ thì hiện thẻ.
 *  Kết thúc: đăng lại thành post mới (để có thông báo; ngoài DM thì @nhắc thật người giao việc) rồi xoá post stream. */
export class InlineReply {
  private postId = "";
  private text = "";
  private lastMsg = "";
  private timer: Timer | null = null;
  private creating: Promise<void> | null = null;
  private chain: Promise<void> = Promise.resolve();
  card!: RunCard;
  approval: Record<string, any> | null = null; // lời xin duyệt nằm ngay trong post (props.flygo_agent_approval)
  extra: Record<string, any> | null = null; // props thêm của post trả lời (vd. flygo_agent_link khi trả lời agent khác)

  broadcast = false; // trong luồng: tin cuối gửi cả ra chat chính (thread_broadcast)
  private lastSent = ""; // bỏ lần sửa trùng nội dung
  private held = false; // đang chờ người duyệt / trả lời: không sửa post (trừ lời xin duyệt)
  private heldDirty = false;

  /** where.root_id rỗng = chat chính; có = trong luồng (props.flygo_reply). */
  constructor(private mm: MM, private where: { channel_id: string; root_id: string }, private runId: string, private engine: string,
    private owner: { id: string; username: string }, private mention: boolean) {}

  private body(streaming: boolean, final = false) {
    const { flygo_reply, ...cardProps } = this.card.props() as any;
    return {
      message: this.text.trim() ? this.text : this.card.render(),
      props: {
        ...(this.where.root_id ? { flygo_reply: final && this.broadcast ? "thread_broadcast" : "thread" } : {}),
        ...cardProps,
        flygo_agent_message: { run_id: this.runId, engine: this.engine, seq: 1, streaming, ...(final ? { final: true } : {}) },
        ...(this.approval && !final ? { flygo_agent_approval: this.approval } : {}),
        ...(this.extra ?? {}),
      },
    };
  }

  get id() { return this.postId; }
  private finalId = "";
  /** Sau khi lượt xong (tác vụ nền còn chạy): sửa props của post hiện tại (post cuối, hoặc post giữ thẻ khi lỗi) theo thẻ mới. */
  async patchProps() {
    if (!this.postId) return;
    await this.mm.patchPost(this.postId, { props: this.body(false, true).props }).catch(() => {});
  }
  /** chữ agent đã viết tới giờ */
  get current() { return this.text; }
  /** id post đang stream (tạo ngay nếu chưa có). */
  async ensurePost(): Promise<string> {
    if (!this.postId && !this.creating) this.schedule(0);
    await this.creating;
    return this.postId;
  }
  /** Đặt / bỏ lời xin duyệt trên post, sửa ngay. */
  async setApproval(a: Record<string, any> | null) {
    this.approval = a;
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    this.push();
    await this.chain;
  }
  /** Đưa post đang stream xuống cuối chat / luồng (sau thẻ câu hỏi, tin chèn của người): đăng post mới cùng nội dung
   *  rồi xoá post cũ. Không làm vậy thì sau khi Sếp trả lời, phần đang làm (spinner, bước mới) nằm phía trên thẻ câu hỏi,
   *  cuối màn hình chỉ còn thẻ "Đã trả lời · vừa xong" như lượt đã xong (Sếp 2026-11-22: "phản hồi lâu mà không có loading"). */
  async moveToEnd(): Promise<boolean> {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    await this.creating;
    await this.chain;
    if (!this.postId) return false;
    const old = this.postId;
    const p = await this.mm.createPost({ ...this.where, ...this.body(true) }).catch(() => null);
    if (!p) return false;
    this.postId = p.id;
    this.lastSent = "";
    await this.mm.deletePost(old).catch(() => {});
    return true;
  }
  private segN = 0;
  /** Các post cũ của lượt (trước tin chèn của người): vẫn sửa khi phần cũ đổi (bước đang chạy xong…). */
  private segs: { id: string; seg: Segment; runId: string; last: string }[] = [];
  private segBody(x: { seg: Segment; runId: string }) {
    const props: any = this.card.segmentProps(x.seg);
    const msg = this.card.segmentText(x.seg);
    return {
      message: msg.trim() ? msg : this.card.render(),
      props: {
        ...(this.where.root_id ? { flygo_reply: "thread" } : {}),
        ...props,
        flygo_agent_message: { run_id: x.runId, engine: this.engine, seq: 1, streaming: false },
        ...(this.extra ?? {}),
      },
    };
  }
  private pushSegs() {
    for (const x of this.segs) {
      const b = this.segBody(x);
      const key = JSON.stringify(b);
      if (key === x.last) continue;
      x.last = key;
      this.chain = this.chain.then(() => this.mm.patchPost(x.id, b).then(() => {}, () => { x.last = ""; }));
    }
  }
  /** Người vừa chèn tin vào lượt đang chạy: post đang stream GIỮ NGUYÊN chỗ (khép thành một đoạn, kế hoạch / tác vụ nền
   *  chuyển xuống), mọi chữ / bước MỚI từ giờ là POST MỚI dưới tin của người; phần cũ (bước đang chạy dở…) vẫn được sửa
   *  tại chỗ ở post cũ (Sếp 25/11). Đoạn cũ mang run_id riêng (`<run>~N`) nên app không xoá khi tin cuối được đăng.
   *  Đoạn hiện tại còn trống thì chỉ đưa post xuống dưới (không để lại post rỗng). */
  async splitHere(): Promise<boolean> {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    await this.creating;
    await this.chain;
    if (!this.postId) return false;
    if (this.card.segmentEmpty) return this.moveToEnd();
    const x = { id: this.postId, seg: this.card.segmentStart(), runId: `${this.runId}~${++this.segN}`, last: "" };
    this.segs.push(x);
    this.pushSegs();
    await this.chain;
    // Đoạn mới: post mới (thẻ "đang làm") ngay dưới tin của người.
    this.postId = "";
    this.text = "";
    this.lastMsg = "";
    this.lastSent = "";
    this.creating = null;
    this.schedule(0);
    await this.creating;
    return !!this.postId;
  }
  /** Chờ người (duyệt / trả lời câu hỏi): ngừng sửa post; thôi chờ thì sửa một lần nếu có thay đổi. */
  hold(on: boolean) {
    this.held = on;
    if (!on && this.heldDirty) { this.heldDirty = false; this.schedule(0); }
  }
  private push() {
    this.pushSegs();
    const b = this.body(true);
    const key = JSON.stringify(b);
    if (key === this.lastSent) return;
    this.chain = this.chain.then(() => {
      if (!this.postId) return;
      this.lastSent = key;
      return this.mm.patchPost(this.postId, b).then(() => {}, () => { this.lastSent = ""; });
    });
  }

  /** Thẻ đổi trạng thái/bước. */
  touch() { this.schedule(800); }

  update(u: { id: string; delta?: string; full?: string; done?: boolean }) {
    this.card.text(u); // giữ mọi đoạn (props.flygo_agent.texts); post.message vẫn là đoạn đang / cuối
    if (u.id !== this.lastMsg) { this.lastMsg = u.id; if (u.full === undefined) this.text = ""; } // tin mới của agent thay tin trước
    if (u.full !== undefined) this.text = u.full; else this.text += u.delta ?? "";
    if (this.card.status === "thinking") this.card.status = "running";
    this.schedule(500);
  }

  private schedule(delay: number) {
    if (!this.postId && !this.creating) {
      this.creating = this.mm.createPost({ ...this.where, ...this.body(true) }).then((p) => { this.postId = p.id; }, () => {});
      this.chain = this.creating;
      return;
    }
    if (this.held) { this.heldDirty = true; return; }
    if (this.timer) return;
    this.timer = setTimeout(() => { this.timer = null; this.push(); }, delay);
  }

  /** text: câu trả lời cuối (rỗng khi lỗi/dừng: giữ post, chỉ chốt thẻ). */
  async finish(text: string) {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    this.pushSegs(); // bước cuối của các đoạn cũ (đang chạy -> xong)
    await this.chain;
    if (text.trim()) this.text = text;
    if (!this.text.trim()) {
      const b = this.body(false, true);
      if (this.postId) await this.mm.patchPost(this.postId, b).catch(() => {});
      else await this.mm.createPost({ ...this.where, ...b }).catch(() => {});
      return;
    }
    const b = this.body(false, true);
    const prefix = this.mention ? mentionPrefix(this.owner.username, b.message) : "";
    const fin = await this.mm.createPost({ ...this.where, message: prefix + b.message, props: b.props }, this.mention ? [this.owner.username] : []);
    this.finalId = fin?.id ?? "";
    if (this.postId) await this.mm.deletePost(this.postId).catch(() => {});
    if (this.finalId) this.postId = this.finalId;
  }
}
