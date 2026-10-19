import { useState, useSyncExternalStore } from "react";
import type { NoteDraft } from "./noteDraft";

interface Props {
  draft: NoteDraft;
  /** Back to typing in the note. */
  onKeep(): void;
  /** The input now lives in a new note at `path`: open it in this one's place. */
  onOpenCopy(path: string): void;
  /** The input was dropped and the disk holds nothing to show: close the note, saying why. */
  onLetGo(reason: string): void;
}

/**
 * 保存冲突: the note changed elsewhere while the editor held input not yet saved. Nothing is
 * decided for the user, and nothing they typed is dropped unless they say so.
 */
export function ConflictNotice({ draft, onKeep, onOpenCopy, onLetGo }: Props) {
  const notice = useSyncExternalStore(draft.subscribe, () => draft.notice);
  const message = useSyncExternalStore(draft.subscribe, () => draft.message);
  const unavailable = useSyncExternalStore(draft.subscribe, () => draft.unavailable);
  const [problem, setProblem] = useState<string>();
  if (!notice) return null;

  const keep = () => {
    draft.keepInput();
    onKeep();
  };
  const copy = async () => {
    const saved = await draft.saveCopy();
    if ("path" in saved) onOpenCopy(saved.path);
    else setProblem(saved.error);
  };
  // Drops the input, so it asks first: for the version on disk, or for nothing when there is none.
  const reload = async () => {
    const sure = await window.notes.confirm(
      unavailable
        ? { message: "放弃你的输入？", detail: "这篇笔记在磁盘上已无法打开，放弃后会关闭它，还没有保存的输入会丢失。", action: "放弃输入" }
        : { message: "放弃你的输入，重新载入？", detail: "将显示磁盘上的版本，还没有保存的输入会丢失。", action: "放弃输入并重新载入" },
    );
    if (!sure) return;
    const { gone } = await draft.reload();
    if (gone !== undefined) onLetGo(gone);
    else onKeep();
  };

  return (
    <div className="conflict" role="alert" aria-label="保存冲突">
      <p className="conflict-text">
        {message}你的输入还没有保存，仍保留在编辑器中。{problem}
      </p>
      <div className="conflict-actions">
        <button onClick={keep}>保留输入</button>
        <button onClick={() => void copy()}>另存副本</button>
        <button onClick={() => void reload()}>{unavailable ? "放弃输入…" : "重新载入…"}</button>
      </div>
    </div>
  );
}
