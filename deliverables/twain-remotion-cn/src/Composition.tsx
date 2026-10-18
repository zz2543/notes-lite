import { TransitionSeries } from "@remotion/transitions";
import { staticFile, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";
import { Opening } from "./scenes/Opening";
import { Writing } from "./scenes/Writing";
import { Agent } from "./scenes/Agent";
import { Review } from "./scenes/Review";
import { Research } from "./scenes/Research";
import { Spaces } from "./scenes/Spaces";
import { Workflow } from "./scenes/Workflow";
import { Closing } from "./scenes/Closing";
import { duration } from "./shared";

export const TwainPromo = () => {
  const { fps } = useVideoConfig();
  return (
    <>
      <Audio
        name="轻量原创配乐"
        src={staticFile("score.wav")}
        premountFor={fps}
        volume={0.65}
      />
      <TransitionSeries>
        <TransitionSeries.Sequence
          name="共笔"
          durationInFrames={duration("Opening")}
          premountFor={fps}
        >
          <Opening />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="本地写作"
          durationInFrames={duration("Writing")}
          premountFor={fps}
        >
          <Writing />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="AI 协作"
          durationInFrames={duration("Agent")}
          premountFor={fps}
        >
          <Agent />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="修改审阅"
          durationInFrames={duration("Review")}
          premountFor={fps}
        >
          <Review />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="资料研究"
          durationInFrames={duration("Research")}
          premountFor={fps}
        >
          <Research />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="可视化空间"
          durationInFrames={duration("Spaces")}
          premountFor={fps}
        >
          <Spaces />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="开放工作流"
          durationInFrames={duration("Workflow")}
          premountFor={fps}
        >
          <Workflow />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="你掌舵，AI 执笔"
          durationInFrames={duration("Closing")}
          premountFor={fps}
        >
          <Closing />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </>
  );
};
