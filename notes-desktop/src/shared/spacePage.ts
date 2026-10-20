// Between a space homepage's preload and main; the app's own page never uses these. A module of its
// own: sandboxed preloads cannot load shared chunks, so the two preloads must not import a common file.
export const spacePageChannels = {
  request: "space-page:request",
  changed: "space-page:changed",
  /** homepage → main: an error its scripts, resources or components ran into (the 错误条). */
  error: "space-page:error",
  /** main → homepage: the page settings as CSS, replacing the style element that holds them. */
  settings: "space-page:settings",
} as const;
