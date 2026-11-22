import { expect, test } from "bun:test";
import { cleanDeep, cleanText, shrinkPost } from "./safe-text";

test("bỏ NUL và ký tự điều khiển, giữ tab / xuống dòng", () => {
  expect(cleanText("a\u0000b\u0007c\td\ne\rf")).toBe("abc\td\ne\rf");
  expect(cleanText("bình thường 😀")).toBe("bình thường 😀");
});
test("surrogate lẻ thành U+FFFD, cặp đúng giữ nguyên", () => {
  expect(cleanText("x\uD83Dy")).toBe("x�y");
  expect(cleanText("x\uDE00y")).toBe("x�y");
  expect(cleanText("😀")).toBe("😀");
});
test("làm sạch sâu message + props (thẻ chạy có kết quả tool)", () => {
  const p = cleanDeep({ message: "ok\u0000", props: { flygo_run: { steps: [{ title: "đọc tệp", output: "<x>\u0000</x>" }], n: 3, on: true, z: null } } });
  expect(p).toEqual({ message: "ok", props: { flygo_run: { steps: [{ title: "đọc tệp", output: "<x></x>" }], n: 3, on: true, z: null } } });
  expect(JSON.stringify(p)).not.toContain("\\u0000");
});
test("rút gọn tin để gửi lại", () => {
  const s = shrinkPost({ message: "a".repeat(20), props: { x: "b".repeat(10), k: 1 } }, 5, 4);
  expect(s.message!.startsWith("aaaaa\n…")).toBe(true);
  expect(s.props!.x.startsWith("bbbb\n…")).toBe(true);
  expect(s.props!.k).toBe(1);
});

test("gọi nhiều lần liên tiếp vẫn làm sạch (regex không giữ trạng thái)", () => {
  for (let i = 0; i < 5; i++) expect(cleanText(`a\u0000b${i}`)).toBe(`ab${i}`);
});
