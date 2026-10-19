// PROTOTYPE sample data — in memory only, never touches a real notes library.

export const folders = [
  { id: "daily", name: "日常", children: [{ id: "daily/scraps", name: "随记", children: [] }] },
  { id: "projects", name: "项目", children: [] },
  { id: "reading", name: "阅读", children: [{ id: "reading/excerpts", name: "摘录", children: [] }] },
];

export const notes = [
  {
    id: "n1", folder: "daily", date: "10/19", title: "给思考留一点空白",
    blocks: [
      ["p", "写下正在发生的想法，让它们慢慢长成自己的形状。"],
      ["h2", "今天，从一件小事开始"],
      ["p", "不急着整理，也不急着得出答案。把一句话、一束光、一个值得追问的问题，留在这里。用 Markdown 写作，文件永远是你自己的。"],
      ["quote", "好的记录，是与自己的下一次相遇。"],
      ["li", "读完书后，留下一个问题"],
      ["li", "散步时，记下偶然的发现"],
      ["li", "给明天的自己留一句话"],
    ],
  },
  {
    id: "n2", folder: "daily", date: "10/18", title: "稍后再想的事",
    blocks: [["p", "让未完成的想法也有一个安放的地方。"], ["li", "换一个 Electron 窗口材质试试"], ["li", "Mica 和 vibrancy 的差别"]],
  },
  {
    id: "n3", folder: "daily/scraps", date: "10/17", title: "清晨的片段",
    blocks: [["p", "窗边的光刚好落在纸上，今天想慢一点开始。"], ["p", "咖啡还没凉，第一行字已经写下。"]],
  },
  {
    id: "n4", folder: "daily/scraps", date: "10/16", title: "雨后的散步",
    blocks: [["p", "经过那棵树时，发现叶子比昨天更绿了一点。"], ["quote", "城市在雨后会安静三分钟。"]],
  },
  {
    id: "n5", folder: "projects", date: "10/15", title: "跨平台重写计划",
    blocks: [
      ["p", "以 Electron 单一代码库重写，macOS 为主，Windows 为辅。"],
      ["h2", "四个里程碑"],
      ["li", "骨架：打开笔记库、编辑与自动保存"],
      ["li", "编辑对齐：列表、光标、选区、专注模式"],
      ["li", "空间：空间主页与操作记录"],
      ["li", "完成对齐：Windows、动效、性能"],
    ],
  },
  {
    id: "n6", folder: "projects", date: "10/14", title: "动效预设",
    blocks: [["p", "轻弹、滑移、展开、浮现。所有界面只用这四种。"], ["p", "越常用的操作越轻快，越少用的越有表现力。"]],
  },
  {
    id: "n7", folder: "reading", date: "10/12", title: "读书摘记",
    blocks: [["p", "阅读是让熟悉的事物重新变得陌生。见 给思考留一点空白。"], ["quote", "Typography exists to honor content."]],
  },
  {
    id: "n8", folder: "reading/excerpts", date: "10/10", title: "关于留白",
    blocks: [["p", "留白让文字之间也能呼吸。"], ["p", "版心不必太宽，行距不必太紧。"]],
  },
  {
    id: "n9", folder: "projects", date: "10/08", title: "下一步",
    blocks: [["p", "把复杂的事拆成眼前可以开始的一步。整理线索，再动手。"]],
  },
  {
    id: "n10", folder: "daily", date: "10/05", title: "一个还没有命名的想法",
    blocks: [],
  },
];

export const spaces = [
  { id: "fit", icon: "🏋️", name: "健身", scope: "健身, 日记" },
  { id: "ielts", icon: "📚", name: "雅思", scope: "雅思" },
  { id: "read", icon: "📖", name: "阅读", scope: "阅读" },
];

export function inFolder(note, folderId) {
  if (!folderId) return true;
  return note.folder === folderId || note.folder.startsWith(folderId + "/");
}

export function summary(note) {
  const first = note.blocks.find((b) => b[0] === "p" || b[0] === "li");
  return first ? first[1] : "";
}

export function pathOf(note) {
  const names = { daily: "日常", "daily/scraps": "日常/随记", projects: "项目", reading: "阅读", "reading/excerpts": "阅读/摘录" };
  return names[note.folder] ?? "";
}
