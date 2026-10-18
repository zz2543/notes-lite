import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Img,
  getRemotionEnvironment,
  Easing,
  Interactive,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Audio } from "@remotion/media";
import type { Caption } from "@remotion/captions";
import data from "./timing.json";

type Timing = {
  duration: number;
  clips: { file: string; from: number; duration: number }[];
  captions: Caption[];
};
export const timing = data as Record<string, Timing>;
export const duration = (id: string) =>
  Math.round((timing[id]?.duration ?? 10) * 30);
export const colors = {
  ink: "#202124",
  blue: "#007aff",
  muted: "#737780",
  paper: "#f6f7f9",
};
export const font =
  '-apple-system, "PingFang SC", "Helvetica Neue", sans-serif';
export const ease = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
  easing: Easing.bezier(0.16, 1, 0.3, 1),
} as const;

// Native WebKit previews do not paint CanvasImage consistently; Chromium export does.
export const Picture = (props: {
  src: string;
  premountFor: number;
  style: React.CSSProperties;
}) =>
  getRemotionEnvironment().isRendering ? (
    <CanvasImage {...props} />
  ) : (
    <Img {...props} />
  );

export const SceneAudio = ({ id }: { id: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const scene = timing[id];
  const caption = scene?.captions.find(
    (c) => (frame / fps) * 1000 >= c.startMs && (frame / fps) * 1000 < c.endMs,
  );
  return (
    <>
      {scene?.clips.map((c) => (
        <Sequence
          key={c.file}
          name={c.file}
          from={Math.round(c.from * fps)}
          durationInFrames={Math.ceil(c.duration * fps)}
          premountFor={fps}
        >
          <Audio src={staticFile(c.file)} premountFor={fps} />
        </Sequence>
      ))}
      {caption && (
        <Interactive.Div
          name="中文字幕"
          style={{
            position: "absolute",
            bottom: 36,
            left: 140,
            right: 140,
            display: "flex",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              fontFamily: font,
              color: colors.ink,
              fontSize: 32,
              lineHeight: 1.45,
              padding: "12px 28px",
              background: "rgba(255,255,255,.96)",
              border: "1px solid #e6e8ec",
              borderRadius: 8,
              textAlign: "center",
              maxWidth: 1560,
            }}
          >
            {caption.text}
          </div>
        </Interactive.Div>
      )}
    </>
  );
};
export const Base = ({ children }: { children: React.ReactNode }) => (
  <AbsoluteFill
    style={{ background: colors.paper, color: colors.ink, fontFamily: font }}
  >
    {children}
  </AbsoluteFill>
);

export const Header = ({
  number,
  title,
  subtitle,
}: {
  number: string;
  title: string;
  subtitle: string;
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Interactive.Div
      name="功能标题"
      style={{
        position: "absolute",
        left: 110,
        top: 65,
        right: 110,
        opacity: interpolate(frame, [0, 0.7 * fps], [0, 1], ease),
        translate: interpolate(
          frame,
          [0, 0.9 * fps],
          ["0px 22px", "0px 0px"],
          ease,
        ),
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontSize: 23,
          color: colors.muted,
        }}
      >
        <span style={{ color: colors.blue }}>共笔 / Twain</span>
        <span>{number}</span>
      </div>
      <div
        style={{
          fontSize: 70,
          lineHeight: 1.2,
          fontWeight: 650,
          marginTop: 24,
        }}
      >
        {title}
      </div>
      <div
        style={{
          fontSize: 29,
          lineHeight: 1.5,
          color: colors.muted,
          marginTop: 16,
        }}
      >
        {subtitle}
      </div>
    </Interactive.Div>
  );
};

type FeatureProps = {
  id: string;
  number: string;
  title: string;
  subtitle: string;
  image: string;
  focus: [number, number];
  label: string;
};
export const Feature = ({
  id,
  number,
  title,
  subtitle,
  image,
  focus,
  label,
}: FeatureProps) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Base>
      <Header number={number} title={title} subtitle={subtitle} />
      <Interactive.Div
        name="应用界面"
        style={{
          position: "absolute",
          left: 110,
          top: 300,
          width: 1030,
          height: 660,
          borderRadius: 18,
          overflow: "hidden",
          boxShadow: "0 18px 50px rgba(0,0,0,.09)",
          border: "1px solid rgba(128,128,128,.16)",
          opacity: interpolate(frame, [0.2 * fps, 1 * fps], [0, 1], ease),
          translate: interpolate(
            frame,
            [0.2 * fps, 1.1 * fps],
            ["0px 35px", "0px 0px"],
            ease,
          ),
        }}
      >
        <Picture
          src={staticFile(image)}
          premountFor={fps}
          style={{ width: "100%", height: "100%", objectFit: "fill" }}
        />
        <div
          style={{
            position: "absolute",
            left: `${focus[0] * 100}%`,
            top: `${focus[1] * 100}%`,
            width: 50,
            height: 50,
            border: "2px solid #007aff",
            borderRadius: "50%",
            opacity: interpolate(frame, [1.8 * fps, 4 * fps], [0, 1], ease),
            scale: interpolate(frame, [2 * fps, 3 * fps], [1.4, 1], ease),
          }}
        />
      </Interactive.Div>
      <Interactive.Div
        name="细节放大"
        style={{
          position: "absolute",
          left: 1200,
          top: 385,
          width: 610,
          height: 430,
          opacity: interpolate(frame, [1.8 * fps, 4 * fps], [0, 1], ease),
          translate: interpolate(
            frame,
            [1.8 * fps, 4 * fps],
            ["25px 0px", "0px 0px"],
            ease,
          ),
        }}
      >
        <div style={{ fontSize: 31, fontWeight: 600, marginBottom: 24 }}>
          {label}
        </div>
        <div
          style={{
            height: 360,
            width: 610,
            overflow: "hidden",
            borderRadius: 18,
            border: "1px solid rgba(128,128,128,.18)",
            boxShadow: "0 16px 45px rgba(0,0,0,.1)",
            background: "white",
            position: "relative",
          }}
        >
          <Picture
            src={staticFile(image)}
            premountFor={fps}
            style={{
              position: "absolute",
              width: 1820,
              height: 1166,
              left: Math.max(-1210, Math.min(0, 305 - focus[0] * 1820)),
              top: Math.max(-806, Math.min(0, 180 - focus[1] * 1166)),
              scale: interpolate(
                frame,
                [4 * fps, duration(id)],
                [1, 1.035],
                ease,
              ),
            }}
          />
        </div>
        <div style={{ fontSize: 20, color: colors.muted, marginTop: 18 }}>
          应用界面截图 · 功能细节
        </div>
      </Interactive.Div>
      <SceneAudio id={id} />
    </Base>
  );
};
