/**
 * How the window's bottom layer (side panel and list) is drawn: the system material, or the opaque
 * --win-fallback colour where there is none.
 */
export type WindowMaterial = "vibrancy" | "mica" | "opaque";

/** What the main process knows about the system's look before the page loads. */
export interface Appearance {
  material: WindowMaterial;
  /** The system accent colour as #rrggbb, or null when the system does not say. */
  accent: string | null;
}

// The appearance reaches the page as switches on its command line, read by the preload before any script.
const switches = { material: "--window-material=", accent: "--system-accent=" };
const materials: readonly WindowMaterial[] = ["vibrancy", "mica", "opaque"];
const hexColour = /^#[0-9a-f]{6}$/i;

export function appearanceArguments({ material, accent }: Appearance): string[] {
  return [switches.material + material, ...(accent ? [switches.accent + accent] : [])];
}

export function readAppearance(argv: readonly string[]): Appearance {
  const value = (prefix: string) => argv.find((arg) => arg.startsWith(prefix))?.slice(prefix.length);
  const accent = value(switches.accent);
  return {
    material: materials.find((m) => m === value(switches.material)) ?? "opaque",
    accent: accent && hexColour.test(accent) ? accent : null,
  };
}
