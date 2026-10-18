import {
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Base, colors, ease, Picture, SceneAudio } from "../shared";
export const Closing = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Base>
      <Interactive.Div
        name="片尾品牌"
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          paddingBottom: 100,
          opacity: interpolate(frame, [0, fps], [0, 1], ease),
          translate: interpolate(
            frame,
            [0, 1.2 * fps],
            ["0px 24px", "0px 0px"],
            ease,
          ),
        }}
      >
        <Picture
          src={staticFile("icon.png")}
          premountFor={fps}
          style={{ width: 132, height: 132, marginBottom: 30 }}
        />
        <div
          style={{
            fontFamily: '"Songti SC", serif',
            fontSize: 110,
            fontWeight: 700,
          }}
        >
          共笔{" "}
          <span
            style={{
              fontFamily: "Georgia, serif",
              fontSize: 65,
              fontWeight: 400,
            }}
          >
            Twain
          </span>
        </div>
        <div style={{ fontSize: 48, marginTop: 32 }}>你掌舵，AI 执笔。</div>
        <div
          style={{
            display: "flex",
            gap: 32,
            marginTop: 48,
            color: colors.blue,
            fontSize: 32,
          }}
        >
          <span>记录</span>
          <span style={{ color: colors.muted }}>→</span>
          <span>思考</span>
          <span style={{ color: colors.muted }}>→</span>
          <span>行动</span>
        </div>
      </Interactive.Div>
      <SceneAudio id="Closing" />
    </Base>
  );
};
