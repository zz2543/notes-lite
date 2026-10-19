/**
 * How the window's bottom layer (side panel and list) is drawn: the system material, or the opaque
 * --win-fallback colour where there is none.
 */
export type WindowMaterial = "vibrancy" | "mica" | "opaque";

/** What the main process knows about the system's look before the page loads. */
export interface Appearance {
  material: WindowMaterial;
}

// The appearance reaches the page as switches on its command line, read by the preload before any script.
const switches = { material: "--window-material=" };
const materials: readonly WindowMaterial[] = ["vibrancy", "mica", "opaque"];

export function appearanceArguments({ material }: Appearance): string[] {
  return [switches.material + material];
}

export function readAppearance(argv: readonly string[]): Appearance {
  const value = (prefix: string) => argv.find((arg) => arg.startsWith(prefix))?.slice(prefix.length);
  return { material: materials.find((m) => m === value(switches.material)) ?? "opaque" };
}
