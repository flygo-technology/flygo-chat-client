import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRIDGE_EXTENSION_ID, launchCommand, profilesWithExtension, userDataDirs } from "./browser-local";

function fakeChrome() {
  const ud = mkdtempSync(join(tmpdir(), "chrome-ud-"));
  writeFileSync(join(ud, "Local State"), JSON.stringify({ profile: { info_cache: {
    "Default": { name: "Cá nhân", user_name: "" },
    "Profile 8": { name: "Ba", user_name: "duongvanba6868@gmail.com" },
    "Profile 9": { name: "Tắt", user_name: "off@x.vn" },
  } } }));
  const prof = (dir: string, file: string, settings: any) => { mkdirSync(join(ud, dir), { recursive: true }); writeFileSync(join(ud, dir, file), JSON.stringify({ extensions: { settings } })); };
  prof("Default", "Preferences", { other: {} });
  prof("Profile 8", "Secure Preferences", { [BRIDGE_EXTENSION_ID]: { location: 4, path: "/x/flygo-chat-extension" } });
  prof("Profile 9", "Secure Preferences", { [BRIDGE_EXTENSION_ID]: { location: 4, state: 0, disable_reasons: [1] } });
  prof("Profile 12", "Preferences", { [BRIDGE_EXTENSION_ID]: { state: 1 } }); // không có trong Local State
  return ud;
}

test("profilesWithExtension: chỉ profile có extension đang bật, kèm tên + email", () => {
  const ps = profilesWithExtension(fakeChrome());
  expect(ps.map((p) => p.dir)).toEqual(["Profile 8", "Profile 12"]);
  expect(ps[0]).toMatchObject({ name: "Ba", email: "duongvanba6868@gmail.com" });
});

test("launchCommand: macOS mở nền bằng open -gna, tham số tách (không qua shell)", () => {
  const [p] = profilesWithExtension(fakeChrome());
  expect(launchCommand(p, "darwin")).toEqual({ cmd: "open", args: ["-gna", "Google Chrome", "--args", "--profile-directory=Profile 8"] });
});

test("userDataDirs theo hệ điều hành", () => {
  expect(userDataDirs("darwin", "/Users/a")[0].dir).toBe("/Users/a/Library/Application Support/Google/Chrome");
  expect(userDataDirs("linux", "/home/a")[0].dir).toBe("/home/a/.config/google-chrome");
  expect(userDataDirs("win32", "C:\\Users\\a", { LOCALAPPDATA: "C:\\Users\\a\\AppData\\Local" })[0].dir).toContain("Chrome");
});

test("kysoLaunch: mở nền đúng profile, kiểm url / profile", async () => {
  const { kysoLaunch } = await import("./browser-local");
  expect(kysoLaunch({ tax: "0110804395", url: "https://e-declaration.customs.gov.vn:8443/eclare-ui/" }, "darwin"))
    .toEqual({ cmd: "open", args: ["-g", "-a", "Trinh duyet Ky so da nang", "--args", "--hidden", "--profile-tax=0110804395", "--url=https://e-declaration.customs.gov.vn:8443/eclare-ui/"] });
  expect(kysoLaunch({ url: "javascript:alert(1)" }, "darwin")).toEqual({ error: "url phải là http(s)" });
  expect(kysoLaunch({ profile: "a/b; rm -rf" }, "darwin")).toEqual({ error: "profile phải dạng <agentId>/<tokenId>" });
});
