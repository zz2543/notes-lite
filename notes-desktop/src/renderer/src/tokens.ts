// Icon sizes from the design system ("图标"); CSS sizes live as variables in styles.css.
export const icon = { regular: 17, small: 15, caret: 11 } as const;

// 助手栏 (设计规范, 尺寸 and 助手形象).
/** 助手形象 sizes: at the top of the 助手栏, and on the card's toggle while the column is closed. */
export const figureSize = { column: 48, toggle: 22 } as const;
/** While the 助手栏 is open the side navigation narrows below these window widths: 双栏, then 单栏, then 图标栏. */
export const assistantBreakpoints = { single: 1180, rail: 960 } as const;
