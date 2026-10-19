import { motion } from "motion/react";
import { useMotion } from "./MotionProvider";

/**
 * 选中底板: rendered inside the selected row. When the selection moves, the pill slides from the old row
 * to the new one with 滑移; when its own row moves (a folder above it opens), it moves with the row.
 */
export function SelectionPill({ group }: { group: "side" | "list" }) {
  const { slide } = useMotion();
  return (
    <motion.span layoutId={`${group}-pill`} transition={slide} className={`pill ${group}`} data-testid="selection-pill" aria-hidden />
  );
}
