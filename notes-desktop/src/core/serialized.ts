// Writes to one library made on behalf of space homepages (and their undoing) run one at a time,
// whichever space sends them, so two of them never interleave the read and write of one note.
const queues = new Map<string, Promise<unknown>>();

export function serialized<T>(root: string, run: () => Promise<T>): Promise<T> {
  const previous = queues.get(root) ?? Promise.resolve();
  const next = previous.then(run, run);
  const settled = next.catch(() => undefined);
  queues.set(root, settled);
  void settled.then(() => queues.get(root) === settled && queues.delete(root));
  return next;
}
