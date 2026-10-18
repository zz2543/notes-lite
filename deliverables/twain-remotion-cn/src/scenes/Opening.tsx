import {
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Base, colors, ease, Picture, SceneAudio } from "../shared";

export const Opening = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Base>
      <Interactive.Div
        name="共笔品牌"
        style={{
          position: "absolute",
          left: 110,
          top: 280,
          opacity: interpolate(frame, [0, fps], [0, 1], ease),
          translate: interpolate(
            frame,
            [0, 1.2 * fps],
            ["0px 30px", "0px 0px"],
            ease,
          ),
        }}
      >
        <Picture
          src={staticFile("icon.png")}
          premountFor={fps}
          style={{ width: 110, height: 110, marginBottom: 28 }}
        />
        <div
          style={{
            fontSize: 116,
            fontFamily: '"Songti SC", serif',
            fontWeight: 700,
          }}
        >
          共笔{" "}
          <span
            style={{
              fontSize: 64,
              fontFamily: "Georgia, serif",
              fontWeight: 400,
            }}
          >
            Twain
          </span>
        </div>
        <div style={{ fontSize: 45, marginTop: 32 }}>你掌舵，AI 执笔。</div>
        <div style={{ fontSize: 27, color: colors.muted, marginTop: 22 }}>
          本地笔记 · AI 协作 · 开放接口
        </div>
      </Interactive.Div>
      <Interactive.Div
        name="产品窗口"
        style={{
          position: "absolute",
          left: 885,
          top: 150,
          width: 1130,
          height: 730,
          borderRadius: 20,
          overflow: "hidden",
          boxShadow: "0 28px 65px rgba(0,0,0,.12)",
          opacity: interpolate(frame, [0.5 * fps, 1.6 * fps], [0, 1], ease),
          translate: interpolate(
            frame,
            [0.5 * fps, 2 * fps],
            ["80px 0px", "0px 0px"],
            ease,
          ),
        }}
      >
        <Picture
          src={staticFile("screens/editor-light.jpg")}
          premountFor={fps}
          style={{ width: 1130, height: 730 }}
        />
      </Interactive.Div>
      <SceneAudio id="Opening" />
    </Base>
  );
};
