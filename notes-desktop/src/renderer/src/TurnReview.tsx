import { CaretRight } from "@phosphor-icons/react";
import { useEffect, useState } from "react";
import type { DiffLine } from "../../core";
import type { ChangeKind, Reply, TurnChange } from "../../shared/conversation";
import { icon } from "./tokens";

// 写入审查 (assistant-spec, ticket 29): after a turn that changed anything, one card lists what it
// changed. 全部保留 is the default; a note can be opened to see its lines and taken back alone, or
// the whole turn taken back. What it wrote outside the library has no snapshot and can't be.

/** Asks main to keep the turn or take something back; answers why it couldn't, if it couldn't. */
export type ReviewAction = (action: "keep" | "revert", path?: string) => Promise<string | undefined>;

const verbs: Record<ChangeKind, string> = { added: "新建", modified: "改写", deleted: "删除" };

function Diff({ turn, path }: { turn: string; path: string }) {
  const [lines, setLines] = useState<DiffLine[] | null | string>();
  useEffect(() => {
    let live = true;
    void window.notes.turnDiff(turn, path).then((diff) => live && setLines(diff.ok ? diff.lines : diff.message));
    return () => {
      live = false;
    };
  }, [turn, path]);
  if (lines === undefined) return <p className="review-diff-note">正在读取改动…</p>;
  if (lines === null) return <p className="review-diff-note">附件没有逐行差异。</p>;
  if (typeof lines === "string") return <p className="review-diff-note">{lines}</p>;
  if (lines.length === 0) return <p className="review-diff-note">内容没有变化。</p>;
  return (
    <pre className="review-diff" aria-label={`${path} 的改动`}>
      {lines.map((line, i) => (
        <span key={i} className={line.sign === "+" ? "added" : "removed"}>
          {`${line.sign} ${line.text}\n`}
        </span>
      ))}
    </pre>
  );
}

function ChangeRow({ turn, change, busy, onRevert }: { turn: string; change: TurnChange; busy: boolean; onRevert(): void }) {
  const [open, setOpen] = useState(false);
  return (
    <li className={change.reverted ? "review-row reverted" : "review-row"}>
      <div className="review-line">
        <button type="button" className="review-file" aria-expanded={open} aria-label={`查看 ${change.path} 的改动`} onClick={() => setOpen(!open)}>
          <CaretRight size={icon.caret} className="timeline-caret" />
          <span className="review-kind">{verbs[change.kind]}</span>
          <span className="review-path">{change.path}</span>
          {change.lines && (
            <span className="review-lines">
              <span className="added">+{change.lines.added}</span> <span className="removed">−{change.lines.removed}</span>
            </span>
          )}
        </button>
        {change.reverted ? (
          <span className="review-state">已撤回</span>
        ) : change.restorable ? (
          <button type="button" className="review-revert" aria-label={`撤回 ${change.path}`} disabled={busy} onClick={onRevert}>
            撤回
          </button>
        ) : (
          <span className="review-state" title="只记录了大小和时间">
            无法撤回
          </span>
        )}
      </div>
      {open && <Diff turn={turn} path={change.path} />}
    </li>
  );
}

/** The card while the turn waits on its review; once kept or taken back, one line says so. */
export function TurnReview({ reply, onReview, onShowLog }: { reply: Reply; onReview: ReviewAction; onShowLog(): void }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string>();
  const changes = reply.changes ?? [];
  const outside = reply.outside ?? [];
  const count = changes.length + outside.length;
  const act = async (action: "keep" | "revert", path?: string) => {
    setBusy(true);
    setProblem(await onReview(action, path));
    setBusy(false);
  };

  if (reply.review === "reverted") return <p className="reply-changes">已撤回本轮改动。</p>;
  if (reply.review !== "pending")
    return (
      <p className="reply-changes">
        {reply.review === "kept" ? `已保留本轮改动（${count} 个文件）。` : `改动了 ${count} 个文件。`}
        {reply.entry && (
          <button type="button" className="reply-log" onClick={onShowLog}>
            在操作记录中撤销
          </button>
        )}
      </p>
    );

  const restorable = changes.some((c) => c.restorable && !c.reverted);
  return (
    <section className="turn-review" aria-label="本轮改动">
      <p className="review-head">本轮改动了 {count} 个文件</p>
      <ul className="review-list">
        {changes.map((change) => (
          <ChangeRow key={change.path} turn={reply.turn!} change={change} busy={busy} onRevert={() => void act("revert", change.path)} />
        ))}
        {outside.map((path) => (
          <li key={path} className="review-row">
            <div className="review-line">
              <span className="review-file outside">
                <CaretRight size={icon.caret} className="timeline-caret" aria-hidden />
                <span className="review-kind">笔记库以外</span>
                <span className="review-path" title={path}>
                  {path}
                </span>
              </span>
              <span className="review-state">不可撤销</span>
            </div>
          </li>
        ))}
      </ul>
      {problem && (
        <p className="reply-failed" role="alert">
          {problem}
        </p>
      )}
      <div className="review-buttons">
        {restorable && (
          <button type="button" className="secondary" disabled={busy} onClick={() => void act("revert")}>
            撤回本轮
          </button>
        )}
        <button type="button" className="primary" disabled={busy} onClick={() => void act("keep")}>
          全部保留
        </button>
      </div>
    </section>
  );
}
