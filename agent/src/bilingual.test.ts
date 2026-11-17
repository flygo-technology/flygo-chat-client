import { expect, test } from "bun:test";
import { bilingualOf } from "./bilingual";

test("song ngữ: ghép nội dung + props nút cờ; thiếu / sai mã / trùng ngôn ngữ báo lỗi; không có tham số = tin thường", () => {
  expect(bilingualOf({}, "xin chào")).toBeNull();
  expect(bilingualOf({ lang: "th", translation: "Chào anh", translation_lang: "vi" }, "สวัสดีค่ะ")).toEqual({
    message: "สวัสดีค่ะ\n\n───\nChào anh",
    props: { flygo_bilingual: { v: 1, langs: ["th", "vi"], texts: ["สวัสดีค่ะ", "Chào anh"] } },
  });
  expect(bilingualOf({ lang: "TH-th", translation: "x", translation_lang: "vi_VN" }, "y")).toMatchObject({ props: { flygo_bilingual: { langs: ["th", "vi"] } } });
  expect(bilingualOf({ lang: "th", translation_lang: "vi" }, "y")).toHaveProperty("error");
  expect(bilingualOf({ lang: "thai", translation: "x", translation_lang: "vi" }, "y")).toHaveProperty("error");
  expect(bilingualOf({ lang: "vi", translation: "x", translation_lang: "vi" }, "y")).toHaveProperty("error");
});
