import { useEffect, useState } from "react";
import type { LogItem } from "../../shared/api";
import { Dialog } from "./Organize";

// 操作记录: what space homepages wrote and what each assistant turn changed, reachable from a space's
// homepage, from a turn's reply in the 助手栏 and from the 笔记 menu, with or without any space.

const time = new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });

/** Opened from the menu (笔记 › 操作记录…) as well as from wherever the page offers it. */
export function useOperationLog(notify: (message: string) => void) {
  const [open, setOpen] = useState(false);
  useEffect(() => window.notes.onOperationLogRequest(() => setOpen(true)), []);
  const dialog = open ? <OperationLogDialog onClose={() => setOpen(false)} notify={notify} /> : null;
  return { show: () => setOpen(true), dialog };
}

/** The last 30 days, newest first, each entry undoable on its own. */
function OperationLogDialog({ onClose, notify }: { onClose(): void; notify(message: string): void }) {
  const [items, setItems] = useState<LogItem[]>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    void window.notes.operationLog().then((read) => {
      if (!live) return;
      if (read.ok) setItems(read.value);
      else {
        setItems([]);
        notify(read.message);
      }
    });
    return () => {
      live = false;
    };
  }, [revision]);
  const undo = async (item: LogItem) => {
    const undone = await window.notes.undoOperation(item.id);
    if (!undone.ok) notify(undone.message);
    setRevision((n) => n + 1);
  };
  return (
    <Dialog title="操作记录" onClose={onClose} onSubmit={onClose}>
      <p className="dialog-hint">空间主页的每次写入和助手每一轮的改动都记在这里，保留 30 天，可以逐条撤销。</p>
      {items?.length === 0 && <p className="dialog-hint">还没有操作记录。</p>}
      {items && items.length > 0 && (
        <ul className="dialog-list log-list">
          {items.map((item) => (
            <li key={item.id} className={`log-item ${item.undone ? "undone" : ""}`}>
              <div className="log-text">
                <span className="log-summary">{item.summary}</span>
                <span className="log-meta">
                  {item.space} · {time.format(new Date(item.date))}
                  {item.undone && " · 已撤销"}
                </span>
                {item.changes.length > 0 && (
                  <pre className="log-changes">{item.changes.map((change) => `${change.sign} ${change.text}`).join("\n")}</pre>
                )}
              </div>
              {!item.undone && (
                <button type="button" className="secondary" onClick={() => void undo(item)}>
                  撤销
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      <div className="dialog-buttons">
        <button type="submit" className="primary">
          关闭
        </button>
      </div>
    </Dialog>
  );
}
