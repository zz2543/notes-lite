import {
  Interactive,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Base, colors, ease, Header, SceneAudio } from "../shared";

export const Workflow = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const code =
    "---\ntitle: 润色选中段落\nagent: claude\nscope: selection\n---\n\n保留原意，把这段写得更简洁：\n{{selection}}";
  return (
    <Base>
      <Header
        number="06 / 工作流"
        title="把常做的事，变成顺手的事。"
        subtitle="自定义命令 / 事件自动化 / CLI 与 MCP 开放接口"
      />
      <Interactive.Div
        name="命令文件示例"
        style={{
          position: "absolute",
          left: 110,
          top: 325,
          width: 800,
          height: 580,
          border: "1px solid #e0e3e7",
          background: "white",
          borderRadius: 16,
          overflow: "hidden",
          opacity: interpolate(frame, [0.3 * fps, 1.2 * fps], [0, 1], ease),
        }}
      >
        <div
          style={{
            padding: "24px 30px",
            background: "#f0f1f4",
            color: colors.muted,
            fontSize: 23,
            borderBottom: "1px solid #e0e3e7",
          }}
        >
          .twain/commands/polish.md
        </div>
        <pre
          style={{
            fontFamily: 'Menlo, "PingFang SC", monospace',
            whiteSpace: "pre-wrap",
            padding: "12px 32px",
            fontSize: 28,
            lineHeight: 1.75,
            color: "#2c3542",
          }}
        >
          {code.slice(
            0,
            Math.floor(
              interpolate(frame, [fps, 3.2 * fps], [0, code.length], ease),
            ),
          )}
        </pre>
      </Interactive.Div>
      <Interactive.Div
        name="开放接口"
        style={{
          position: "absolute",
          left: 1010,
          top: 390,
          width: 790,
          opacity: interpolate(frame, [2 * fps, 3.2 * fps], [0, 1], ease),
        }}
      >
        <div style={{ fontSize: 42, fontWeight: 600 }}>连接你已有的工具</div>
        <div style={{ fontSize: 28, color: colors.muted, marginTop: 24 }}>
          笔记、上下文、搜索与数据
        </div>
        <div
          style={{
            background: "#232529",
            padding: "32px 36px",
            borderRadius: 16,
            fontFamily: "Menlo, monospace",
            marginTop: 38,
            fontSize: 30,
            lineHeight: 2,
            color: "white",
          }}
        >
          <span style={{ color: "#67d791" }}>$</span> twain context
          <br />
          <span style={{ color: "#67d791" }}>$</span> twain search 灵感
          <br />
          <span style={{ color: "#67d791" }}>$</span> twain data add
        </div>
        <div style={{ fontSize: 20, color: colors.muted, marginTop: 20 }}>
          命令配置与接口示例
        </div>
      </Interactive.Div>
      <SceneAudio id="Workflow" />
    </Base>
  );
};
