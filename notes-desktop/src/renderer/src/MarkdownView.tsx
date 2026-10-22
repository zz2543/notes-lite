import { useEffect, useRef, type ReactNode } from "react";
import {
  blockType,
  displayMath,
  isTableSeparator,
  literalBlocks,
  parseLine,
  parseTable,
  shownSpan,
  type BlockType,
  type InlineSpan,
  type LineMarkup,
  type TableCell,
} from "../../shared/markdown";
import { renderTex } from "./tex";

// Markdown, read-only, as the 助手栏 shows an assistant's reply: headings, lists and tasks, quotes, code
// and math blocks, tables, rules, and inline emphasis, code, links and formulas. It reads the text with
// the editor's own parser (shared/markdown.ts), so a reply looks as it would in a note; it builds React
// elements, never HTML, so nothing an agent writes can run in the page. Web links open in the browser.

/** A formula, typeset by KaTeX (loaded the first time one is shown). React leaves the element's insides to it. */
function Tex({ tex, display }: { tex: string; display: boolean }) {
  const el = useRef<HTMLElement>(null);
  useEffect(() => {
    if (el.current) renderTex(el.current, tex, display);
  }, [tex, display]);
  return display ? <div ref={el as React.RefObject<HTMLDivElement>} className="md-math-block" /> : <span ref={el} className="md-math" />;
}

const external = (url: string) => /^(https?:|mailto:)/i.test(url.trim());

function wrap(span: InlineSpan, children: ReactNode, key: string): ReactNode {
  switch (span.kind) {
    case "bold":
      return <strong key={key}>{children}</strong>;
    case "italic":
      return <em key={key}>{children}</em>;
    case "strike":
      return <s key={key}>{children}</s>;
    case "highlight":
      return <mark key={key}>{children}</mark>;
    case "code":
      return <code key={key}>{children}</code>;
    case "tag":
      return (
        <span key={key} className="md-tag">
          {children}
        </span>
      );
    case "footnote":
      return <sup key={key}>{children}</sup>;
    case "link":
    case "image": {
      const url = (span.value ?? "").trim();
      if (!external(url)) {
        return (
          <span key={key} className="md-link" title={url}>
            {children}
          </span>
        );
      }
      return (
        <a
          key={key}
          className="md-link"
          href={url}
          title={url}
          onClick={(event) => {
            event.preventDefault();
            void window.notes.openExternal(url);
          }}
        >
          {children}
        </a>
      );
    }
    default:
      // [[笔记]] and ![[附件]]: named, not followed (a reply is not in any note).
      return (
        <span key={key} className="md-link" title={span.value}>
          {children}
        </span>
      );
  }
}

/** The text of `line` from `from`, its syntax hidden and each run wrapped in the spans that cover it. */
function Inline({ line, from, spans }: { line: string; from: number; spans: InlineSpan[] }): ReactNode {
  const shown = spans.map((span) => ({ span, ...shownSpan(span) }));
  // Outer spans first, so a run's wrappers nest the same way each time.
  shown.sort((a, b) => a.content.from - b.content.from || b.content.to - a.content.to);
  const out: ReactNode[] = [];
  let i = from;
  while (i < line.length) {
    const math = shown.find((s) => s.span.kind === "math" && s.content.from <= i && i < s.content.to);
    if (math) {
      out.push(<Tex key={`m${i}`} tex={math.span.value ?? line.slice(math.content.from, math.content.to)} display={false} />);
      i = math.content.to;
      continue;
    }
    if (shown.some((s) => s.marks.some((m) => m.from <= i && i < m.to))) {
      i += 1;
      continue;
    }
    const covering = shown.filter((s) => s.content.from <= i && i < s.content.to);
    const key = covering.map((s) => shown.indexOf(s)).join(",");
    let end = i + 1;
    while (end < line.length) {
      if (shown.some((s) => s.marks.some((m) => m.from <= end && end < m.to))) break;
      const next = shown.filter((s) => s.content.from <= end && end < s.content.to);
      if (next.map((s) => shown.indexOf(s)).join(",") !== key) break;
      end += 1;
    }
    let node: ReactNode = line.slice(i, end);
    for (let k = covering.length - 1; k >= 0; k--) node = wrap(covering[k]!.span, node, `${k}`);
    out.push(<span key={i}>{node}</span>);
    i = end;
  }
  return out;
}

const markupOf = (line: string, type: BlockType = blockType(line)) => parseLine(line, type);
const inlineOf = (line: string, markup: LineMarkup) => <Inline line={line} from={markup.prefix.to} spans={markup.spans} />;

function Cell({ cell, header, align }: { cell: TableCell; header: boolean; align: string }) {
  const markup = markupOf(cell.text, "p");
  const Tag = header ? "th" : "td";
  return <Tag style={{ textAlign: align as "left" }}>{inlineOf(cell.text, markup)}</Tag>;
}

interface Item {
  line: string;
  markup: LineMarkup;
}

const isList = (type: BlockType) => type === "li" || type === "ol" || type === "task";

/** Nested lists from consecutive items: deeper items go inside the item before them. */
function listFrom(items: Item[], start: number, depth: number, key: string): { node: ReactNode; next: number } {
  const ordered = items[start]!.markup.type === "ol";
  const entries: { item: Item; nested: ReactNode[] }[] = [];
  let i = start;
  while (i < items.length) {
    const item = items[i]!;
    if (item.markup.depth < depth) break;
    if (item.markup.depth > depth) {
      const { node, next } = listFrom(items, i, item.markup.depth, `${key}-${i}`);
      if (entries.length) entries.at(-1)!.nested.push(node);
      else entries.push({ item, nested: [node] });
      i = next;
      continue;
    }
    if ((item.markup.type === "ol") !== ordered) break;
    entries.push({ item, nested: [] });
    i += 1;
  }
  const lis = entries.map(({ item, nested }, n) => {
    const { line, markup } = item;
    const task = markup.type === "task";
    const checked = task && /\[[xX]\]/.test(line.slice(markup.prefix.from, markup.prefix.to));
    return (
      <li key={n} className={task ? (checked ? "md-task done" : "md-task") : undefined}>
        {task && <input type="checkbox" checked={checked} disabled readOnly aria-label={checked ? "已完成" : "未完成"} />}
        {inlineOf(line, markup)}
        {nested}
      </li>
    );
  });
  const first = Number.parseInt(items[start]!.line.trim(), 10);
  const node = ordered ? (
    <ol key={key} start={Number.isFinite(first) && first !== 1 ? first : undefined}>
      {lis}
    </ol>
  ) : (
    <ul key={key}>{lis}</ul>
  );
  return { node, next: i };
}

/** The blocks of some Markdown lines. */
function blocksOf(lines: string[], key: string): ReactNode[] {
  const out: ReactNode[] = [];
  const literal = new Map(literalBlocks(lines).map((block) => [block.first, block]));
  let i = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    const k = `${key}-${i}`;
    const block = literal.get(i);
    if (block) {
      const inner = lines.slice(block.first + 1, block.closed ? block.last : block.last + 1).join("\n");
      if (block.kind === "math" && block.closed) out.push(<Tex key={k} tex={inner} display />);
      else if (block.kind !== "frontmatter") {
        out.push(
          <pre key={k} className="md-code">
            <code>{inner}</code>
          </pre>,
        );
      }
      i = block.last + 1;
      continue;
    }
    const type = blockType(line);
    if (type === "empty") {
      i += 1;
      continue;
    }
    const tex = line.includes("$$") ? displayMath(line) : null;
    if (tex !== null) {
      out.push(<Tex key={k} tex={tex} display />);
      i += 1;
      continue;
    }
    if (line.trimStart().startsWith("|") && i + 1 < lines.length && isTableSeparator(lines[i + 1]!)) {
      let last = i + 1;
      while (last + 1 < lines.length && lines[last + 1]!.trimStart().startsWith("|")) last += 1;
      const table = parseTable(lines.slice(i, last + 1).map((l) => l.trim()));
      if (table) {
        out.push(
          <div key={k} className="md-table">
            <table>
              <thead>
                <tr>
                  {table.header.map((cell, c) => (
                    <Cell key={c} cell={cell} header align={table.aligns[c]!} />
                  ))}
                </tr>
              </thead>
              <tbody>
                {table.rows.map((row, r) => (
                  <tr key={r}>
                    {row.map((cell, c) => (
                      <Cell key={c} cell={cell} header={false} align={table.aligns[c]!} />
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>,
        );
        i = last + 1;
        continue;
      }
    }
    if (type === "hr") {
      out.push(<hr key={k} />);
      i += 1;
      continue;
    }
    if (/^h[1-6]$/.test(type)) {
      const Tag = type as "h1";
      out.push(
        <Tag key={k} className="md-heading">
          {inlineOf(line, markupOf(line, type))}
        </Tag>,
      );
      i += 1;
      continue;
    }
    if (type === "quote") {
      let last = i;
      while (last + 1 < lines.length && blockType(lines[last + 1]!) === "quote") last += 1;
      const inner = lines.slice(i, last + 1).map((l) => l.replace(/^> ?/, ""));
      out.push(<blockquote key={k}>{blocksOf(inner, k)}</blockquote>);
      i = last + 1;
      continue;
    }
    if (isList(type)) {
      const items: Item[] = [];
      while (i < lines.length && isList(blockType(lines[i]!)) && !literal.has(i)) {
        items.push({ line: lines[i]!, markup: markupOf(lines[i]!) });
        i += 1;
      }
      for (let n = 0; n < items.length; ) {
        const { node, next } = listFrom(items, n, items[n]!.markup.depth, `${k}-${n}`);
        out.push(node);
        n = next;
      }
      continue;
    }
    // A paragraph: consecutive lines of text, each line break kept.
    const paragraph: string[] = [];
    while (i < lines.length && !literal.has(i)) {
      const next = lines[i]!;
      const nextType = blockType(next);
      if (nextType !== "p" && nextType !== "table") break;
      if (paragraph.length && (displayMath(next) !== null || (next.trimStart().startsWith("|") && isTableSeparator(lines[i + 1] ?? "")))) break;
      paragraph.push(next);
      i += 1;
    }
    if (!paragraph.length) {
      // A line of a kind not drawn above (a lone table row, say): as text.
      paragraph.push(line);
      i += 1;
    }
    out.push(
      <p key={k}>
        {paragraph.map((text, n) => (
          <span key={n}>
            {n > 0 && <br />}
            {inlineOf(text, markupOf(text, "p"))}
          </span>
        ))}
      </p>,
    );
  }
  return out;
}

/** Markdown text as read-only blocks. */
export function MarkdownView({ text, className }: { text: string; className?: string }) {
  return <div className={className}>{blocksOf(text.replace(/\r\n?/g, "\n").split("\n"), "b")}</div>;
}
