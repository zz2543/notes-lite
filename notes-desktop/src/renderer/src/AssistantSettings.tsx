import { useEffect, useState } from "react";
import type { SnapshotUsage } from "../../core";
import type { ReviewMode } from "../../shared/preferences";
import { Segmented, type Choice } from "./controls";
import { usePreferences } from "./preferences";
import { SettingRow, SettingsGroup } from "./SettingsPanel";

// 设置 › 助手 (assistant-spec): 写入审查, whether a card follows each turn; the 快照 taken before each
// turn, how much disk they take, and clearing them.

const reviewModes: Choice<ReviewMode>[] = [
  { value: "review", label: "每轮结束后审查" },
  { value: "keep", label: "直接保留" },
];

/** Bytes as the settings panel shows them: KB below a megabyte, then MB, then GB. */
export function diskSize(bytes: number): string {
  if (bytes === 0) return "没有快照";
  const units = ["KB", "MB", "GB"];
  let size = bytes / 1024;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return `${size >= 10 ? Math.round(size) : Math.max(0.1, Math.round(size * 10) / 10)} ${units[unit]}`;
}

export function AssistantPage() {
  const { preferences, change } = usePreferences();
  const [usage, setUsage] = useState<SnapshotUsage>();
  const [clearing, setClearing] = useState(false);
  const measure = () => void window.notes.snapshotUsage().then(setUsage);
  useEffect(measure, []);

  const clear = async () => {
    const go = await window.notes.confirm({
      message: "立即清理全部快照？",
      detail: "清理后，助手此前各轮的改动都不能再撤销。",
      action: "立即清理",
    });
    if (!go) return;
    setClearing(true);
    await window.notes.clearSnapshots().finally(() => setClearing(false));
    measure();
  };

  return (
    <>
      <SettingsGroup
        title="写入审查"
        description="助手直接改写笔记库，审查发生在每一轮结束之后：一张卡片列出这一轮改过的笔记，默认全部保留，也可以逐篇撤回。选择“直接保留”就不再出现卡片，改动仍可在操作记录中撤销。"
      >
        <SettingRow label="审查方式">
          <Segmented label="审查方式" choices={reviewModes} value={preferences.assistantReview} onChange={(assistantReview) => change({ assistantReview })} />
        </SettingRow>
      </SettingsGroup>
      <SettingsGroup
        title="快照"
        description="助手每一轮开始前，会为整个笔记库做一次快照，用来审查和撤销这一轮的改动。快照存在应用自己的数据目录，保留 30 天后自动清理。笔记库以外的文件不在快照范围内，无法撤销。"
      >
        <SettingRow label="快照占用">
          <output aria-label="快照占用">{usage ? diskSize(usage.bytes) : "正在计算…"}</output>
        </SettingRow>
        <SettingRow label="清理">
          <button className="settings-action" onClick={() => void clear()} disabled={clearing || !usage || usage.bytes === 0}>
            立即清理
          </button>
        </SettingRow>
        {usage && !usage.attachmentsKept && (
          <p className="settings-row settings-warning">笔记库的附件太大，无法逐一复制：附件只记录大小和修改时间，助手改动的附件无法撤回。</p>
        )}
      </SettingsGroup>
    </>
  );
}
