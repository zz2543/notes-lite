import { useState, useSyncExternalStore } from "react";
import type { NoteDraft } from "./noteDraft";

interface Props {
  draft: NoteDraft;
  /** Back to typing. */
  onKeep(): void;
  /** The input now lives in a new note at `path`: open it in this one's place. */
  onOpenCopy(path: string): void;
}

/**
 * 保存冲突: the note changed elsewhere while the editor held input not yet saved. Nothing is
 * decided for the user, and nothing they typed is dropped unless they say so.
 */
export function ConflictNotice({ draft, onKeep, onOpenCopy }: Props) {
  const notice = useSyncExternalStore(draft.subscribe, () => draft.notice);
  const message = useSyncExternalStore(draft.subscribe, () => draft.message);
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

  return (
    <div className="conflict" role="alert" aria-label="保存冲突">
      <p className="conflict-text">
        {message}你的输入还没有保存，仍保留在编辑器中。{problem}
      </p>
      <div className="conflict-actions">
        <button onClick={keep}>保留输入</button>
        <button onClick={() => void copy()}>另存副本</button>
      </div>
    </div>
  );
}
