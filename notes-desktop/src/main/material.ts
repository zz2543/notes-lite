import type { BrowserWindowConstructorOptions } from "electron";
import type { WindowMaterial } from "../shared/appearance";

// Electron draws Mica from Windows 11 22H2 (build 22621) on.
const micaBuild = 22621;

/** The design system's 材质 table: vibrancy on macOS, Mica on Windows 11, the opaque colour otherwise. */
export function windowMaterial({ platform, release, frameless }: { platform: NodeJS.Platform; release: string; frameless: boolean }): WindowMaterial {
  if (platform === "darwin") return "vibrancy";
  // Electron only extends Mica under the page of a frameless window; a framed one would show black there.
  if (platform === "win32" && frameless && Number(release.split(".")[2]) >= micaBuild) return "mica";
  return "opaque";
}

// --win-fallback from the design system, needed before any CSS has loaded.
const fallback = { light: "#f2f1f5", dark: "#1e1e22" };

/**
 * Window options for the material. With a material the background colour is left out, so Electron keeps
 * it transparent; without one the window is the fallback colour from the first frame, with no white flash.
 */
export function materialWindowOptions(material: WindowMaterial, dark: boolean): BrowserWindowConstructorOptions {
  if (material === "vibrancy") return { vibrancy: "sidebar" };
  if (material === "mica") return { backgroundMaterial: "mica" };
  return { backgroundColor: dark ? fallback.dark : fallback.light };
}
