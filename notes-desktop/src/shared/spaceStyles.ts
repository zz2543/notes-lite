// 风格参考 (2026-10-23 用户确认): six finished dashboards, each a look an agent can follow when it writes
// a homepage. Not a theme over every homepage: the user picks one (or describes their own) each time
// a homepage is generated, so every space can look different. The reference itself, with its design
// notes and code, is installed beside the authoring guide (core/spaceStyles.ts).
import bento from "./spaceStyles/bento.jpg.b64?raw";
import earth from "./spaceStyles/earth.jpg.b64?raw";
import glass from "./spaceStyles/glass.jpg.b64?raw";
import night from "./spaceStyles/night.jpg.b64?raw";
import sky from "./spaceStyles/sky.jpg.b64?raw";
import vivid from "./spaceStyles/vivid.jpg.b64?raw";

export type SpaceStyleId = "sky" | "night" | "glass" | "bento" | "earth" | "vivid";

export interface SpaceStyle {
  id: SpaceStyleId;
  /** Its name, also the reference's file name (风格/晴空.md). */
  name: string;
  /** One line on what it looks like, shown under the preview. */
  summary: string;
  /** The Dribbble shot it was rebuilt from. */
  source: { title: string; url: string };
  /** The preview, a JPEG as base64. */
  preview: string;
}

export const spaceStyles: readonly SpaceStyle[] = [
  {
    id: "sky",
    name: "晴空",
    summary: "天空背景配白色大圆角卡片，橙色胶囊进度条、刻度弧形仪表，带渐变光泽。",
    source: { title: "Fitness Dashboard UI Components", url: "https://dribbble.com/shots/27705472-Fitness-Dashboard-UI-Components" },
    preview: sky,
  },
  {
    id: "night",
    name: "暗夜",
    summary: "黑色指标卡配超大数字，渐变竖条、区间柱、LED 分段柱，一张“今日建议”宽卡配白色圆形箭头。",
    source: { title: "Fitness App Health Metrics Dashboard", url: "https://dribbble.com/shots/27473506-Fitness-App-Health-Metrics-Dashboard" },
    preview: night,
  },
  {
    id: "glass",
    name: "玻璃",
    summary: "深色玻璃小组件，圆点竖线图、波浪线、发光弧形表盘、打卡圆点、涨跌小标签和 + 按钮。",
    source: { title: "App Widget UI", url: "https://dribbble.com/shots/27244970-App-Widget-UI" },
    preview: glass,
  },
  {
    id: "bento",
    name: "便当",
    summary: "大小卡片拼成的灰白格子，黑色高密度细柱、三色进度条、圆点日历、方块心情柱，信息密度高。",
    source: { title: "BoozUI Health & Fitness Dashboard", url: "https://dribbble.com/shots/24747077-BoozUI-Health-Fitness-Dashboard-UI" },
    preview: bento,
  },
  {
    id: "earth",
    name: "大地",
    summary: "棕色大地色系，阶梯圆角折线配气泡、分段时间切换、同心圆弧，绿橙紫三色卡配圆形箭头。",
    source: { title: "Freud UI Kit", url: "https://dribbble.com/shots/23689369-Freud-UI-Kit-AI-Mental-Health-App-Smart-Dashboard-UIUX" },
    preview: earth,
  },
  {
    id: "vivid",
    name: "活力",
    summary: "米色底配白卡和黑卡，一周打卡圆圈、实心空心圆点进度、带百分比的环形图，珊瑚色按钮嵌在卡片缺角里。",
    source: { title: "dynamy Fitness Dashboard", url: "https://dribbble.com/shots/26813558-Fitness-Dashboard-UI-Smart-Activity-Tracking" },
    preview: vivid,
  },
];

/** The folder, beside the authoring guide, holding the references. */
export const spaceStylesFolder = "风格";
