// Dialogs open, the last on top: Esc closes that one wherever the focus is, and the window's own
// shortcuts (⌘K, ⌘J, ⌘⇧M, 专注) wait until the last one is closed.
export const openDialogs: Array<{ close(): void }> = [];

export const dialogOpen = (): boolean => openDialogs.length > 0;
