import { FolderSimple, X } from "@phosphor-icons/react";
import { useEffect, useState } from "react";
import type { InstalledAgent } from "../../core";
import { agents, type AgentId } from "../../shared/agentKinds";
import { AssistantFigure } from "./AssistantFigure";
import { Composer, ConversationView, type AssistantState } from "./AssistantChat";
import type { FigureState } from "./figureModel";
import { Segmented } from "./controls";
import { figureSize, icon } from "./tokens";

// 助手栏 (assistant-spec): the fourth column, docked right of the card on the window material, with its
// figure, the choice of agent, the working directory, the conversation and the input.

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
    if (!open) return;
    detect();
    // The library is snapshotted in the background now, so the first turn starts from it (ticket 27).
    window.notes.prepareSnapshots();
  }, [open]);
  return { installed, detect };
}

export interface AssistantColumnProps {
  open: boolean;
  onClose(): void;
  assistant: AssistantState;
  /** Where the user is: the working directory a new conversation gets, and the open note. */
  folder: string;
  note: string | null;
  libraryName: string;
  onOpenFolder(folder: string): void;
  /** Opens 操作记录, where a turn is undone. */
  onShowLog(): void;
  /** Saves the open note, so the agent reads what is on screen; false when it could not. */
  saveFirst(): Promise<boolean>;
}

export function AssistantColumn({ open, onClose, assistant, folder, note, libraryName, onOpenFolder, onShowLog, saveFirst }: AssistantColumnProps) {
  const { installed, detect } = useInstalledAgents(open);
  const [chosen, setChosen] = useState<AgentId>();
  const agent = installed?.find((a) => a.id === chosen) ?? installed?.[0];
  const { conversation } = assistant;
  // Fixed when the conversation begins; until then it follows the selection.
  const workingFolder = conversation?.folder ?? folder;
  const folderName = workingFolder ? workingFolder.slice(workingFolder.lastIndexOf("/") + 1) : libraryName;
  const conversationAgent = conversation && agents.find((a) => a.id === conversation.agent);
  const send = async (text: string, notes: string[]) => {
    if (!agent || !(await saveFirst())) return;
    await assistant.send({ agent: agent.id, folder, text, notes });
  };
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
          {open && <AssistantFigure size={figureSize.column} state={assistant.figure} />}
          {conversationAgent ? (
            <span className="assistant-agent">{conversationAgent.name}</span>
          ) : (
            installed &&
            installed.length > 0 &&
            agent && <Segmented<AgentId> label="Agent" choices={installed.map((a) => ({ value: a.id, label: a.name }))} value={agent.id} onChange={setChosen} />
          )}
          {installed && installed.length > 0 && (
            <button className="assistant-folder" onClick={() => onOpenFolder(workingFolder)} aria-label={`工作目录：${folderName}`} title="工作目录">
              <FolderSimple size={icon.small} />
              <span>{folderName}</span>
            </button>
          )}
        </header>
        {installed?.length === 0 && <InstallGuide onDetect={detect} />}
        {conversation ? <ConversationView conversation={conversation} onReview={assistant.review} onShowLog={onShowLog} /> : <div className="assistant-messages" />}
        {assistant.problem && (
          <p className="assistant-problem" role="alert">
            {assistant.problem}
          </p>
        )}
        {installed && installed.length > 0 && (
          <Composer
            note={note}
            running={assistant.running}
            disabled={!agent}
            hasConversation={conversation !== null}
            onSend={(text, notes) => void send(text, notes)}
            onStop={assistant.stop}
            onNew={assistant.reset}
          />
        )}
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
