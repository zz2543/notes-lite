// Syntax colouring for one line of a fenced code block, ported from the old NotesCore CodeHighlight.
// Line by line on purpose: the editor restyles single lines as they change, so a token never depends on
// lines above it, except for the usual shape of block comments ("/*", " * ", " */" at a line's start).
// Pure, like markdown.ts.

export type CodeToken = "keyword" | "string" | "comment" | "number" | "type" | "literal" | "tag" | "attribute";

export interface CodeTokenRange {
  from: number;
  to: number;
  token: CodeToken;
}

interface Grammar {
  keywords: Set<string>;
  literals: Set<string>;
  lineComments: string[];
  blockComment?: [string, string];
  quotes: Set<string>;
  /** Capitalised identifiers read as types. */
  capsAreTypes: boolean;
  markup: boolean;
  caseInsensitive: boolean;
}

const words = (list: string) => new Set(list.split(" "));

const cFamily = new Set(
  ("swift js javascript jsx ts typescript tsx java kotlin kt c h cpp c++ cc hpp objc objective-c m cs csharp c# go golang rust rs " +
    "dart scala php css scss less json jsonc groovy gradle zig").split(" "),
);

function grammar(language: string): Grammar | null {
  const g: Grammar = {
    keywords: new Set(),
    literals: words("true false null"),
    lineComments: [],
    quotes: new Set(['"', "'"]),
    capsAreTypes: true,
    markup: false,
    caseInsensitive: false,
  };
  switch (language) {
    case "swift":
      g.keywords = words(
        "func let var if else guard return for in while repeat switch case default break continue struct class enum protocol extension " +
          "import init deinit self Self static private fileprivate public internal open final override mutating throws throw try catch do " +
          "defer where as is some any async await actor typealias associatedtype inout lazy weak unowned super subscript fallthrough rethrows",
      );
      g.literals = words("true false nil");
      break;
    case "js":
    case "javascript":
    case "jsx":
    case "ts":
    case "typescript":
    case "tsx":
    case "mjs":
    case "cjs":
      g.keywords = words(
        "function const let var if else return for of in while do switch case default break continue class extends new this super import " +
          "export from as async await try catch finally throw typeof instanceof delete void yield static get set interface type enum " +
          "implements private public protected readonly declare namespace abstract keyof satisfies",
      );
      g.literals = words("true false null undefined NaN Infinity");
      g.quotes.add("`");
      break;
    case "java":
    case "kotlin":
    case "kt":
    case "scala":
    case "groovy":
    case "gradle":
    case "dart":
      g.keywords = words(
        "public private protected class interface enum extends implements static final void int long double float boolean char byte short " +
          "if else for while do switch case default break continue return new this super import package try catch finally throw throws " +
          "abstract synchronized volatile transient var val fun object when is in as data sealed override open lateinit suspend def trait " +
          "match yield lazy implicit record async await late required",
      );
      g.literals = words("true false null");
      break;
    case "c":
    case "h":
    case "cpp":
    case "c++":
    case "cc":
    case "hpp":
    case "objc":
    case "objective-c":
    case "m":
    case "cs":
    case "csharp":
    case "c#":
    case "zig":
      g.keywords = words(
        "int long short char float double void unsigned signed const static extern struct union enum typedef sizeof if else for while do " +
          "switch case default break continue return goto auto register volatile inline class public private protected virtual override " +
          "template typename namespace using new delete this operator friend try catch throw bool constexpr nullptr noexcept static_cast " +
          "dynamic_cast reinterpret_cast include define ifdef ifndef endif pragma import interface implementation end property self string " +
          "var readonly async await foreach in out ref fn pub comptime",
      );
      g.literals = words("true false NULL nullptr nil YES NO null");
      break;
    case "go":
    case "golang":
      g.keywords = words(
        "func package import var const type struct interface map chan if else for range switch case default break continue return go " +
          "defer select fallthrough goto string int int64 int32 uint byte rune float64 bool error make new len cap append",
      );
      g.literals = words("true false nil iota");
      g.quotes.add("`");
      g.capsAreTypes = false;
      break;
    case "rust":
    case "rs":
      g.keywords = words(
        "fn let mut const static if else match for in while loop break continue return struct enum impl trait type use mod pub crate self " +
          "Self super where as ref move async await dyn unsafe extern i32 i64 u8 u32 u64 usize f32 f64 bool str String Vec Option Result " +
          "Some None Ok Err",
      );
      g.literals = words("true false");
      g.quotes = new Set(['"']);
      break;
    case "php":
      g.keywords = words(
        "function class public private protected static return if else elseif foreach for while as new echo use namespace extends " +
          "implements try catch throw array fn match require include",
      );
      g.lineComments = ["#"];
      break;
    case "css":
    case "scss":
    case "less":
      g.keywords = words("important media import keyframes font-face supports root hover before after");
      g.literals = new Set();
      g.capsAreTypes = false;
      break;
    case "json":
    case "jsonc":
    case "json5":
      g.quotes = new Set(['"']);
      g.capsAreTypes = false;
      break;
    case "python":
    case "py":
    case "python3":
      g.keywords = words(
        "def class return if elif else for while in not and or is import from as with try except finally raise pass break continue " +
          "lambda yield global nonlocal assert del async await self print match case",
      );
      g.literals = words("True False None");
      g.lineComments = ["#"];
      break;
    case "ruby":
    case "rb":
      g.keywords = words(
        "def end class module if elsif else unless while until for in do return yield begin rescue ensure raise require include extend " +
          "attr_accessor self then case when and or not puts lambda proc",
      );
      g.literals = words("true false nil");
      g.lineComments = ["#"];
      break;
    case "sh":
    case "bash":
    case "zsh":
    case "shell":
    case "fish":
    case "console":
    case "shellscript":
    case "powershell":
    case "ps1":
    case "dockerfile":
    case "docker":
    case "makefile":
    case "make":
      g.keywords = words(
        "if then else elif fi for while until do done case esac in function return export local readonly set unset echo cd source exit " +
          "sudo alias FROM RUN CMD COPY ADD WORKDIR ENV EXPOSE ENTRYPOINT ARG LABEL VOLUME USER",
      );
      g.literals = words("true false");
      g.lineComments = ["#"];
      g.quotes.add("`");
      g.capsAreTypes = false;
      break;
    case "yaml":
    case "yml":
    case "toml":
    case "ini":
    case "conf":
    case "properties":
    case "env":
      g.literals = words("true false null yes no on off ~");
      g.lineComments = ["#", ";"];
      g.capsAreTypes = false;
      break;
    case "r":
      g.keywords = words("function if else for while repeat in next break return library require");
      g.literals = words("TRUE FALSE NULL NA Inf NaN");
      g.lineComments = ["#"];
      g.capsAreTypes = false;
      break;
    case "perl":
    case "pl":
      g.keywords = words("my our sub if elsif else unless while for foreach return use package");
      g.lineComments = ["#"];
      break;
    case "sql":
    case "mysql":
    case "postgresql":
    case "postgres":
    case "sqlite":
    case "plsql":
      g.keywords = words(
        "select from where and or not insert into values update set delete create table index view drop alter add join left right inner " +
          "outer on group by order having limit offset as distinct union all case when then else end primary key foreign references " +
          "default unique in is like between exists count sum avg min max with int integer varchar text boolean date timestamp begin " +
          "commit rollback asc desc",
      );
      g.literals = words("null true false");
      g.lineComments = ["--"];
      g.caseInsensitive = true;
      g.capsAreTypes = false;
      break;
    case "lua":
      g.keywords = words("function local if then elseif else end for in do while repeat until return break and or not");
      g.literals = words("true false nil");
      g.lineComments = ["--"];
      break;
    case "haskell":
    case "hs":
    case "elm":
      g.keywords = words("module import where let in case of if then else data type class instance deriving do newtype");
      g.literals = words("True False");
      g.lineComments = ["--"];
      break;
    case "matlab":
    case "octave":
    case "tex":
    case "latex":
      g.keywords = words(
        "function end if else elseif for while return switch case begin documentclass usepackage section subsection label ref cite",
      );
      g.lineComments = ["%"];
      g.capsAreTypes = false;
      break;
    case "html":
    case "xml":
    case "svg":
    case "xhtml":
    case "vue":
    case "plist":
    case "markup":
      g.markup = true;
      g.capsAreTypes = false;
      return g;
    case "diff":
    case "patch":
    case "text":
    case "txt":
    case "plain":
    case "plaintext":
    case "markdown":
    case "md":
    case "mermaid":
    case "":
      return null;
    default:
      // Something code-like: strings, numbers and both common comment styles.
      g.lineComments = ["//", "#"];
      g.blockComment = ["/*", "*/"];
      g.capsAreTypes = false;
      return g;
  }
  if (cFamily.has(language)) {
    g.lineComments.unshift("//");
    g.blockComment = ["/*", "*/"];
  }
  if (language === "css" || language === "scss" || language === "less") g.lineComments = language === "css" ? [] : ["//"];
  return g;
}

const isIdentStart = (c: string) => /[A-Za-z_@$]/.test(c);
const isDigit = (c: string | undefined) => c !== undefined && c >= "0" && c <= "9";

/** Tokens of `line` in `language` (a fence's info string, lowercased). Empty for plain text. */
export function codeTokens(line: string, language: string): CodeTokenRange[] {
  const g = grammar(language);
  if (line === "" || !g) return [];
  if (g.markup) return markupTokens(line);
  const n = line.length;
  const out: CodeTokenRange[] = [];
  const push = (from: number, to: number, token: CodeToken) => out.push({ from, to, token });
  const isIdent = (c: string | undefined) => c !== undefined && (isIdentStart(c) || isDigit(c) || (c === "-" && language.startsWith("css")));
  const keywords = g.caseInsensitive ? new Set([...g.keywords].map((k) => k.toLowerCase())) : g.keywords;

  let i = 0;
  while (i < n && (line[i] === " " || line[i] === "\t")) i++;
  // The inside of a block comment spanning lines: " * text" or "*/".
  if (g.blockComment && line[i] === "*" && (i + 1 >= n || line[i + 1] === " " || line[i + 1] === "/")) return [{ from: i, to: n, token: "comment" }];
  while (i < n) {
    const c = line[i]!;
    if (g.blockComment && line.startsWith(g.blockComment[0], i)) {
      const close = line.indexOf(g.blockComment[1], i + g.blockComment[0].length);
      const end = close < 0 ? n : close + g.blockComment[1].length;
      push(i, end, "comment");
      i = end;
      continue;
    }
    const comment = g.lineComments.find((lc) => line.startsWith(lc, i));
    // "#" only comments at a word boundary (not in "a#b" or "#include"-style C lines).
    if (comment !== undefined && (comment !== "#" || i === 0 || line[i - 1] === " " || line[i - 1] === "\t")) {
      push(i, n, "comment");
      break;
    }
    if (g.quotes.has(c)) {
      let j = i + 1;
      while (j < n && line[j] !== c) j += line[j] === "\\" ? 2 : 1;
      const end = Math.min(n, j + 1);
      push(i, end, "string");
      i = end;
      continue;
    }
    if (isDigit(c) && (i === 0 || !isIdent(line[i - 1]))) {
      let j = i + 1;
      while (j < n && (isIdent(line[j]) || line[j] === ".")) j++;
      push(i, j, "number");
      i = j;
      continue;
    }
    if (isIdentStart(c)) {
      let j = i + 1;
      while (j < n && isIdent(line[j])) j++;
      const word = line.slice(i, j);
      if (c === "@" && j - i > 1) push(i, j, "attribute");
      else if (keywords.has(g.caseInsensitive ? word.toLowerCase() : word)) push(i, j, "keyword");
      else if (g.literals.has(word)) push(i, j, "literal");
      else if (g.capsAreTypes && c >= "A" && c <= "Z" && j - i > 1) push(i, j, "type");
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

/** HTML and XML: tag names, attribute names, quoted values, comments. */
function markupTokens(line: string): CodeTokenRange[] {
  const n = line.length;
  const out: CodeTokenRange[] = [];
  let i = 0;
  while (i < n) {
    if (line.startsWith("<!--", i)) {
      const close = line.indexOf("-->", i + 4);
      const end = close < 0 ? n : close + 3;
      out.push({ from: i, to: end, token: "comment" });
      i = end;
      continue;
    }
    if (line[i] === "<") {
      let j = i + 1;
      if (line[j] === "/" || line[j] === "?" || line[j] === "!") j++;
      const nameStart = j;
      while (j < n && !" >/\t".includes(line[j]!)) j++;
      if (j > nameStart) out.push({ from: nameStart, to: j, token: "tag" });
      // Attributes up to the closing ">".
      while (j < n && line[j] !== ">") {
        const c = line[j]!;
        if (c === '"' || c === "'") {
          let k = j + 1;
          while (k < n && line[k] !== c) k++;
          const end = Math.min(n, k + 1);
          out.push({ from: j, to: end, token: "string" });
          j = end;
          continue;
        }
        if (!" =/\t".includes(c)) {
          const a = j;
          while (j < n && !" =>/".includes(line[j]!)) j++;
          out.push({ from: a, to: j, token: "attribute" });
          continue;
        }
        j++;
      }
      i = j + 1;
      continue;
    }
    i++;
  }
  return out;
}
