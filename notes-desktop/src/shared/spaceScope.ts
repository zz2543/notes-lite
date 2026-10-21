import type { SpaceScope } from "../core/spaces";

/**
 * A space's scope in words: 整个笔记库, or its folders joined with 、 (the root is 笔记库根目录). The title
 * area writes folders as folders (`健身/`); the prompt and the space form write the bare names.
 */
export function scopeLabel(scope: SpaceScope, { asFolders = false } = {}): string {
  if (scope.library) return "整个笔记库";
  return scope.folders.map((folder) => (!folder ? "笔记库根目录" : asFolders ? `${folder}/` : folder)).join("、");
}
