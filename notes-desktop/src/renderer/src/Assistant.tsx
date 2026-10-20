import { X } from "@phosphor-icons/react";
import { useEffect, useState } from "react";
import type { InstalledAgent } from "../../core";
import { agents, type AgentId } from "../../core/agentKinds";
import { AssistantFigure } from "./AssistantFigure";
import type { FigureState } from "./figureModel";
import { Segmented } from "./controls";
import { figureSize, icon } from "./tokens";

// 助手栏 (assistant-spec): the fourth column, docked right of the card on the window material. A turn
// with an agent comes with ticket 28; this is the column, its figure and the choice of agent.

/** ⌘J / Ctrl+J opens and closes the 助手栏. */
export const isAssistantShortcut = (event: KeyboardEvent) =>
  (event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && event.code === "KeyJ";
export const assistantShortcut = navigator.platform.startsWith("Mac") ? "⌘J" : "Ctrl+J";

/** The card's toggle while the column is closed: the small figure, still showing the assistant's state. */
export function AssistantToggle({ state, onOpen }: { state: FigureState; onOpen(): void }) {
  return (
    <button className="assistant-toggle" onClick={onOpen} aria-label="打开助手栏" title={`助手 ${assistantShortcut}`}>
      <AssistantFigure size={figureSize.toggle} state={state} />
    </button>
  );
}

/** How to install each agent, for the guide shown when none is found. */
const installs: Record<AgentId, string | null> = {
  claude: "npm install -g @anthropic-ai/claude-code",
  codex: "npm install -g @openai/codex",
  dsh: null,
  pi: "npm install -g @mariozechner/pi-coding-agent",
};
/** The installed agents, looked for when the column opens and again on request; undefined while looking. */
function useInstalledAgents(open: boolean) {
  const [installed, setInstalled] = useState<InstalledAgent[]>();
  const detect = () => void window.notes.detectAgents().then(setInstalled);
  useEffect(() => {
    if (open) detect();
  }, [open]);
  return { installed, detect };
}

export function AssistantColumn({ open, state, onClose }: { open: boolean; state: FigureState; onClose(): void }) {
  const { installed, detect } = useInstalledAgents(open);
  const [chosen, setChosen] = useState<AgentId>();
  const agent = installed?.find((a) => a.id === chosen) ?? installed?.[0];
  return (
    // Always there, so its width can move; closed, it is hidden from everything once it has shut.
    <aside className={`assistant ${open ? "open" : ""}`} aria-label="助手栏" aria-hidden={!open} inert={!open}>
      <div className="assistant-inner">
        <div className="assistant-bar">
          <button className="icon-button small" onClick={onClose} aria-label="关闭助手栏" title={`关闭 ${assistantShortcut}`}>
            <X size={icon.small} />
          </button>
        </div>
        <header className="assistant-head">
          {/* One figure at a time: the column's only while it is open. */}
          {open && <AssistantFigure size={figureSize.column} state={state} />}
          {installed && installed.length > 0 && agent && (
            <Segmented<AgentId> label="Agent" choices={installed.map((a) => ({ value: a.id, label: a.name }))} value={agent.id} onChange={setChosen} />
          )}
        </header>
        {installed?.length === 0 && <InstallGuide onDetect={detect} />}
      </div>
    </aside>
  );
}

function InstallGuide({ onDetect }: { onDetect(): void }) {
  return (
    <section className="assistant-guide" aria-label="安装 Agent">
      <h2>安装一个命令行 Agent</h2>
      <p>助手通过本机的命令行 Agent 工作。安装下面任意一种，确认在终端里能运行它的命令，再回来重新检测。</p>
      <ul>
        {agents.map((agent) => (
          <li key={agent.id}>
            <span className="guide-name">{agent.name}</span>
            <code>{agent.command}</code>
            {installs[agent.id] && <code className="guide-install">{installs[agent.id]}</code>}
          </li>
        ))}
      </ul>
      <button className="primary" onClick={onDetect}>
        重新检测
      </button>
    </section>
  );
}
