// Between a space homepage's preload and main; the app's own page never uses these. A module of its
// own: sandboxed preloads cannot load shared chunks, so the two preloads must not import a common file.
export const spacePageChannels = {
  request: "space-page:request",
  changed: "space-page:changed",
} as const;
