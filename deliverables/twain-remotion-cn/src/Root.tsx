import { Composition, Folder } from "remotion";
import { TwainPromo } from "./Composition";
import { Opening } from "./scenes/Opening";
import { Writing } from "./scenes/Writing";
import { Agent } from "./scenes/Agent";
import { Review } from "./scenes/Review";
import { Research } from "./scenes/Research";
import { Spaces } from "./scenes/Spaces";
import { Workflow } from "./scenes/Workflow";
import { Closing } from "./scenes/Closing";
import { duration } from "./shared";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="TwainPromo"
        component={TwainPromo}
        width={1920}
        height={1080}
        fps={30}
        durationInFrames={
          duration("Opening") +
          duration("Writing") +
          duration("Agent") +
          duration("Review") +
          duration("Research") +
          duration("Spaces") +
          duration("Workflow") +
          duration("Closing")
        }
      />
      <Folder name="Scenes">
        <Composition
          id="Opening"
          component={Opening}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Opening")}
        />
        <Composition
          id="Writing"
          component={Writing}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Writing")}
        />
        <Composition
          id="Agent"
          component={Agent}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Agent")}
        />
        <Composition
          id="Review"
          component={Review}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Review")}
        />
        <Composition
          id="Research"
          component={Research}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Research")}
        />
        <Composition
          id="Spaces"
          component={Spaces}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Spaces")}
        />
        <Composition
          id="Workflow"
          component={Workflow}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Workflow")}
        />
        <Composition
          id="Closing"
          component={Closing}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={duration("Closing")}
        />
      </Folder>
    </>
  );
};
