import { CaretDown, ClockCounterClockwise, FolderSimple, NotePencil, X } from "@phosphor-icons/react";
import { useEffect, useRef, useState } from "react";
import type { AgentModels, InstalledAgent } from "../../core";
import { agents, modelName, type AgentId } from "../../shared/agentKinds";
import { AssistantFigure } from "./AssistantFigure";
import { Composer, ConversationHistory, ConversationView, folderName, type AssistantState } from "./AssistantChat";
import type { FigureState } from "./figureModel";
import { Segmented } from "./controls";
import { ContextMenu, type Menu } from "./Organize";
import { usePreferences } from "./preferences";
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

/** The models offered for an agent, read from its own configuration when the picker shows. */
function useAgentModels(agent: AgentId) {
  const [models, setModels] = useState<AgentModels>();
  useEffect(() => {
    let live = true;
    void window.notes.agentModels(agent).then((read) => live && setModels(read));
    return () => void (live = false);
  }, [agent]);
  return models;
}

/**
 * 模型选择 (方案 A): beside the agent's name, 默认 (the agent's own settings, named when they say) or a
 * model from its configuration, or one typed in. "" goes back to 默认. An agent that takes its model only
 * from its settings (DeepSeek Harness) shows which, without a choice.
 */
function ModelPicker({ agent, chosen, onChoose }: { agent: AgentId; chosen?: string; onChoose(model: string): void }) {
  const models = useAgentModels(agent);
  const button = useRef<HTMLButtonElement>(null);
  const [menu, setMenu] = useState<Menu>();
  const [typing, setTyping] = useState(false);
  const [typed, setTyped] = useState("");
  const fallback = models?.current ? `默认（${models.current}）` : "默认";
  if (models && !models.choosable)
    return (
      <span className="assistant-model" title="这个 Agent 的模型在它自己的设置里更改">
        模型：{fallback}
      </span>
    );
  if (typing) {
    const typedModel = modelName(typed);
    return (
      <form
        className="assistant-model-typed"
        onSubmit={(event) => {
          event.preventDefault();
          if (!typedModel) return;
          onChoose(typedModel);
          setTyping(false);
        }}
      >
        <input
          autoFocus
          aria-label="模型名称"
          placeholder="模型名称"
          value={typed}
          onChange={(event) => setTyped(event.target.value)}
          onKeyDown={(event) => event.key === "Escape" && setTyping(false)}
          onBlur={() => setTyping(false)}
          spellCheck={false}
        />
      </form>
    );
  }
  const open = () => {
    const at = button.current!.getBoundingClientRect();
    const listed = [...new Set([...(models?.models ?? []), ...(chosen ? [chosen] : [])])];
    setMenu({
      x: at.left,
      y: at.bottom + 4,
      items: [
        { label: fallback, checked: !chosen, run: () => onChoose("") },
        ...listed.map((m) => ({ label: m, checked: chosen === m, run: () => onChoose(m) })),
        "separator" as const,
        {
          label: "手动输入…",
          run: () => {
            setTyped(chosen ?? "");
            setTyping(true);
          },
        },
      ],
    });
  };
  return (
    <>
      <button ref={button} className="assistant-model" onClick={open} aria-haspopup="menu" aria-expanded={Boolean(menu)} aria-label={`模型：${chosen ?? fallback}`} title="模型">
        <span>模型：{chosen ?? fallback}</span>
        <CaretDown size={icon.caret} />
      </button>
      {menu && <ContextMenu {...menu} onClose={() => setMenu(undefined)} />}
    </>
  );
}

/** How to install each agent, for the guide shown when none is found. */
const installs: Record<AgentId, string> = {
  claude: "npm install -g @anthropic-ai/claude-code",
  codex: "npm install -g @openai/codex",
  dsh: "npm install -g @deepseek-ai/dsh",
  pi: "npm install -g @earendil-works/pi-coding-agent",
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
  /** The space open in the card, told to the agent with the spaces' authoring guide. */
  space: string | null;
  libraryName: string;
  onOpenFolder(folder: string): void;
  /** Opens 操作记录, where a turn is undone. */
  onShowLog(): void;
  /** Saves the open note, so the agent reads what is on screen; false when it could not. */
  saveFirst(): Promise<boolean>;
}

export function AssistantColumn({ open, onClose, assistant, folder, note, space, libraryName, onOpenFolder, onShowLog, saveFirst }: AssistantColumnProps) {
  const { installed, detect } = useInstalledAgents(open);
  const [chosen, setChosen] = useState<AgentId>();
  const agent = installed?.find((a) => a.id === chosen) ?? installed?.[0];
  const { conversation } = assistant;
  // Fixed when the conversation begins; until then it follows the selection.
  const workingFolder = conversation?.folder ?? folder;
  const workingName = folderName(workingFolder, libraryName);
  // 对话历史 shows in place of the conversation until one is picked.
  const [history, setHistory] = useState(false);
  const pick = (id: string) => {
    setHistory(false);
    void assistant.open(id);
  };
  const conversationAgent = conversation && agents.find((a) => a.id === conversation.agent);
  // A conversation from 对话历史 whose agent is no longer installed cannot go on.
  const agentGone = conversationAgent && installed && !installed.some((a) => a.id === conversationAgent.id);
  // 模型选择: remembered per agent, for its next new conversation; none is the agent's own default.
  const { preferences, change } = usePreferences();
  const model = agent && preferences.agentModels[agent.id];
  const chooseModel = (id: AgentId, chosen: string) => change({ agentModels: { ...preferences.agentModels, [id]: chosen } });
  const send = async (text: string, notes: string[]) => {
    if (!agent || !(await saveFirst())) return;
    await assistant.send({ agent: agent.id, folder, text, notes, ...(model ? { model } : {}), ...(space ? { space } : {}) });
  };
  return (
    // Always there, so its width can move; closed, it is hidden from everything once it has shut.
    <aside className={`assistant ${open ? "open" : ""}`} aria-label="助手栏" aria-hidden={!open} inert={!open}>
      <div className="assistant-inner">
        <div className="assistant-bar">
          {/* 新对话 sits with 对话历史 at the top; the composer's corner is left for attachments. */}
          <button
            className="icon-button small"
            onClick={() => {
              setHistory(false);
              assistant.reset();
            }}
            disabled={assistant.running || conversation === null}
            aria-label="新对话"
            title="新对话"
          >
            <NotePencil size={icon.small} />
          </button>
          <button
            className="icon-button small"
            onClick={() => setHistory(!history)}
            disabled={assistant.running}
            aria-label="对话历史"
            aria-expanded={history}
            title="对话历史"
          >
            <ClockCounterClockwise size={icon.small} />
          </button>
          <button className="icon-button small" onClick={onClose} aria-label="关闭助手栏" title={`关闭 ${assistantShortcut}`}>
            <X size={icon.small} />
          </button>
        </div>
        <header className="assistant-head">
          {/* One figure at a time: the column's only while it is open. */}
          {open && <AssistantFigure size={figureSize.column} state={assistant.figure} />}
          {/* Beside it, who answers and where they work. */}
          <div className="assistant-identity">
            {conversationAgent ? (
              <span className="assistant-agent">
                {conversationAgent.name}
                {/* The model it began with stays for the whole conversation. */}
                <span className="assistant-model-fixed">{conversation.model ?? "默认模型"}</span>
              </span>
            ) : (
              installed &&
              installed.length > 0 &&
              agent && (
                <>
                  <Segmented<AgentId> label="Agent" choices={installed.map((a) => ({ value: a.id, label: a.name }))} value={agent.id} onChange={setChosen} />
                  <ModelPicker key={agent.id} agent={agent.id} chosen={model || undefined} onChoose={(chosen) => chooseModel(agent.id, chosen)} />
                </>
              )
            )}
            {installed && installed.length > 0 && (
              <button className="assistant-folder" onClick={() => onOpenFolder(workingFolder)} aria-label={`工作目录：${workingName}`} title="工作目录">
                <FolderSimple size={icon.small} />
                <span>{workingName}</span>
              </button>
            )}
          </div>
        </header>
        {installed?.length === 0 && <InstallGuide onDetect={detect} />}
        {history ? (
          <ConversationHistory current={conversation?.id ?? null} libraryName={libraryName} onPick={pick} />
        ) : conversation ? (
          <ConversationView conversation={conversation} onReview={assistant.review} onShowLog={onShowLog} />
        ) : (
          <div className="assistant-messages" />
        )}
        {agentGone && (
          <p className="assistant-problem" role="alert">
            这个对话用的 {conversationAgent.name} 没有安装，不能继续。
          </p>
        )}
        {assistant.problem && (
          <p className="assistant-problem" role="alert">
            {assistant.problem}
          </p>
        )}
        {installed && installed.length > 0 && (
          <Composer
            note={note}
            running={assistant.running}
            disabled={!agent || Boolean(agentGone)}
            hasConversation={conversation !== null}
            onSend={(text, notes) => void send(text, notes)}
            onStop={assistant.stop}
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
            <code className="guide-install">{installs[agent.id]}</code>
          </li>
        ))}
      </ul>
      <button className="primary" onClick={onDetect}>
        重新检测
      </button>
    </section>
  );
}
