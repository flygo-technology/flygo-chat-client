// Tin song ngữ (như nút "Dịch AI" của app, lib/api/translate.dart): nội dung = bản gốc + dòng kẻ + bản dịch (app cũ / app khác
// vẫn đọc được cả hai), props.flygo_bilingual = { v: 1, langs: [gốc, dịch], texts: [gốc, dịch] } để app hiện nút cờ đổi ngôn ngữ.
// Dùng chung cho mọi tool gửi tin (chat_send, chat_reply, chat_schedule_message, chat_report_out, chat_send_bilingual).

export const SEPARATOR = "\n\n───\n";

/** Tham số song ngữ thêm vào schema của tool gửi tin. */
export const BILINGUAL_ARGS = {
  lang: { type: "string", description: "gửi SONG NGỮ (có nút cờ đổi ngôn ngữ): mã ISO 639-1 của message, vd. th" },
  translation: { type: "string", description: "gửi song ngữ: bản dịch của message (tự dịch; giữ @nhắc tên, link, số, emoji). KHÔNG gộp hai bản vào message bằng dòng kẻ" },
  translation_lang: { type: "string", description: "gửi song ngữ: mã ngôn ngữ của bản dịch, vd. vi" },
} as const;

export const BILINGUAL_HINT = " Song ngữ: thêm lang + translation + translation_lang (vd. message tiếng Thái, lang=\"th\", translation=bản tiếng Việt, translation_lang=\"vi\") để người đọc có nút cờ đổi ngôn ngữ; không tự ghép hai bản bằng dòng kẻ.";

const code = (x: unknown) => String(x ?? "").trim().toLowerCase().split(/[-_]/)[0];

/** null = không gửi song ngữ; {error} = tham số sai; còn lại = nội dung + props để gửi. */
export function bilingualOf(a: any, message: string): null | { error: string } | { message: string; props: { flygo_bilingual: { v: 1; langs: [string, string]; texts: [string, string] } } } {
  const anyArg = a?.translation !== undefined || a?.translation_lang !== undefined || a?.lang !== undefined;
  if (!anyArg) return null;
  const t0 = String(message ?? "").trim(), t1 = String(a.translation ?? "").trim(), l0 = code(a.lang), l1 = code(a.translation_lang);
  if (!t0 || !t1) return { error: "Gửi song ngữ cần cả message (bản gốc) và translation (bản dịch)." };
  if (!/^[a-z]{2,3}$/.test(l0) || !/^[a-z]{2,3}$/.test(l1)) return { error: "Gửi song ngữ cần lang và translation_lang là mã ngôn ngữ ISO 639-1 (vi, en, th, ko, ja, zh…)." };
  if (l0 === l1) return { error: "Hai bản cùng một ngôn ngữ: bỏ lang / translation để gửi tin thường." };
  return { message: `${t0}${SEPARATOR}${t1}`, props: { flygo_bilingual: { v: 1, langs: [l0, l1], texts: [t0, t1] } } };
}
