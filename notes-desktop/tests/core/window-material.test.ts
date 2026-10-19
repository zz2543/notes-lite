import { describe, expect, it } from "vitest";
import { materialWindowOptions, windowMaterial } from "../../src/main/material";

// Releases as os.release() reports them: the Darwin kernel on macOS, 10.0.<build> on Windows.
describe("window material", () => {
  it("uses vibrancy on macOS", () => {
    expect(windowMaterial({ platform: "darwin", release: "25.0.0", frameless: false })).toBe("vibrancy");
  });

  it("uses Mica on Windows 11 22H2 and later", () => {
    expect(windowMaterial({ platform: "win32", release: "10.0.22621", frameless: true })).toBe("mica");
    expect(windowMaterial({ platform: "win32", release: "10.0.26100", frameless: true })).toBe("mica");
  });

  it("falls back to the opaque colour on Windows 10 and the first Windows 11 release", () => {
    expect(windowMaterial({ platform: "win32", release: "10.0.19045", frameless: true })).toBe("opaque");
    expect(windowMaterial({ platform: "win32", release: "10.0.22000", frameless: true })).toBe("opaque");
  });

  // Electron only extends Mica under the page for frameless windows; a framed window would show black.
  it("keeps a framed Windows window opaque", () => {
    expect(windowMaterial({ platform: "win32", release: "10.0.26100", frameless: false })).toBe("opaque");
  });

  it("falls back to the opaque colour elsewhere", () => {
    expect(windowMaterial({ platform: "linux", release: "6.8.0", frameless: false })).toBe("opaque");
  });

  it("leaves the window transparent under a material and paints --win-fallback without one", () => {
    expect(materialWindowOptions("vibrancy", false)).toEqual({ vibrancy: "sidebar" });
    expect(materialWindowOptions("mica", true)).toEqual({ backgroundMaterial: "mica" });
    expect(materialWindowOptions("opaque", false)).toEqual({ backgroundColor: "#f2f1f5" });
    expect(materialWindowOptions("opaque", true)).toEqual({ backgroundColor: "#1e1e22" });
  });
});
