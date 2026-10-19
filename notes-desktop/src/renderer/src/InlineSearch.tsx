import { Folder, MagnifyingGlass, X } from "@phosphor-icons/react";
import { useEffect, useRef, useState, type ChangeEvent, type KeyboardEvent } from "react";
import type { SearchHit, SearchResults, Snippet } from "../../core";
import { errorText } from "./ipc";
import { SelectionPill } from "./SelectionPill";
import { icon } from "./tokens";

/** 就地搜索: the whole library by default, or the selected folder with its subfolders. */
export type SearchScope = "library" | "folder";

export interface SearchState {
  /** What the field shows, pinyin still being composed included. */
  text: string;
  /** What is searched: the field's committed text, trimmed. */
  query: string;
  scope: SearchScope;
}

export const startSearch: SearchState = { text: "", query: "", scope: "library" };

export const mac = navigator.userAgent.includes("Mac");
export const searchShortcut = mac ? "⌘K" : "Ctrl+K";

/** ⌘K on macOS, Ctrl+K elsewhere (on macOS Ctrl+K is the editor's own delete-to-end-of-line). */
export const isSearchShortcut = (event: globalThis.KeyboardEvent) =>
  (mac ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === "k";

// More rows than this would only slow the list down; a narrower query finds the rest.
const shownLimit = 100;

interface Answer {
  query: string;
  results?: SearchResults;
  error?: string;
}

/** The latest answer for `query`; the previous one stays until it arrives, so the list never blinks. */
export function useSearch(query: string, folder: string | undefined): Answer | undefined {
  const [answer, setAnswer] = useState<Answer>();
  useEffect(() => {
    if (!query) return;
    let live = true;
    window.notes.search(query, { folder, limit: shownLimit }).then(
      (results) => live && setAnswer({ query, results }),
      (error: unknown) => live && setAnswer({ query, error: errorText(error) }),
    );
    return () => {
      live = false;
    };
  }, [query, folder]);
  return query ? answer : undefined;
}

interface HeadProps {
  state: SearchState;
  /** The selected folder's name, offered as the narrower scope. */
  folderName: string;
  /** Changes whenever the field should take focus again (⌘K while already searching). */
  focusRequest: number;
  onChange(state: SearchState): void;
  /** Enter: open the first result. */
  onSubmit(): void;
  onClose(): void;
}

/** The list header while searching: the search field, then the choice of scope. */
export function SearchHead({ state, folderName, focusRequest, onChange, onSubmit, onClose }: HeadProps) {
  const field = useRef<HTMLInputElement>(null);
  useEffect(() => {
    field.current?.focus();
    field.current?.select();
  }, [focusRequest]);

  // Pinyin being composed is shown but not searched; the committed characters are.
  const onInput = (event: ChangeEvent<HTMLInputElement>) => {
    const text = event.target.value;
    const composing = (event.nativeEvent as InputEvent).isComposing;
    onChange({ ...state, text, query: composing ? state.query : text.trim() });
  };
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Enter" && !event.nativeEvent.isComposing) onSubmit();
  };

  return (
    <header className="list-head search-head">
      <div className="search-box">
        <MagnifyingGlass size={icon.small} />
        <input
          ref={field}
          type="search"
          aria-label="搜索笔记"
          placeholder="搜索标题和正文"
          spellCheck={false}
          value={state.text}
          onChange={onInput}
          onCompositionEnd={(event) => onChange({ ...state, text: event.currentTarget.value, query: event.currentTarget.value.trim() })}
          onKeyDown={onKeyDown}
        />
        <button className="icon-button small" onClick={onClose} aria-label="退出搜索" title="退出搜索 Esc">
          <X size={icon.caret} weight="bold" />
        </button>
      </div>
      <div className="segmented" role="group" aria-label="搜索范围">
        {(
          [
            ["library", "全库"],
            ["folder", `“${folderName}”及子文件夹`],
          ] as const
        ).map(([scope, label]) => (
          <button key={scope} aria-pressed={state.scope === scope} onClick={() => onChange({ ...state, scope })}>
            <span className="label">{label}</span>
          </button>
        ))}
      </div>
    </header>
  );
}

function Highlighted({ snippet }: { snippet: Snippet }) {
  const { text, match } = snippet;
  if (!match) return text;
  return (
    <>
      {text.slice(0, match.start)}
      <mark>{text.slice(match.start, match.end)}</mark>
      {text.slice(match.end)}
    </>
  );
}

interface ResultsProps {
  answer: Answer | undefined;
  libraryName: string;
  openNote: string | null;
  onOpen(hit: SearchHit): void;
}

/** Search results in place of 当前目录内容: title, the matching line, and where the note lives. */
export function SearchResultsList({ answer, libraryName, openNote, onOpen }: ResultsProps) {
  // Until the first answer arrives (the index may still be building), the list stays empty.
  if (!answer) return null;
  if (answer.error) return <p className="empty">{answer.error}</p>;
  const { hits = [], total = 0 } = answer.results ?? {};
  if (total === 0) return <p className="empty">没有找到“{answer.query}”</p>;
  return (
    <>
      <ul className="items" aria-label="搜索结果">
        {hits.map((hit) => (
          <li key={hit.path}>
            <button className={`item result ${openNote === hit.path ? "on" : ""}`} aria-current={openNote === hit.path || undefined} onClick={() => onOpen(hit)}>
              {openNote === hit.path && <SelectionPill group="list" />}
              <span className="label">{hit.title}</span>
              {hit.snippet.text && (
                <span className="snippet">
                  <Highlighted snippet={hit.snippet} />
                </span>
              )}
              <span className="where">
                <Folder size={icon.caret} />
                <span className="label">{hit.folder ? hit.folder.split("/").join(" / ") : libraryName}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {total > hits.length && (
        <p className="empty">
          显示最近修改的 {hits.length} 篇，共 {total} 篇
        </p>
      )}
    </>
  );
}
