import { createContext, useContext, useState, type ReactNode } from "react";
import type { Preferences } from "../../shared/preferences";
import { useAccent } from "./appearance";

interface PreferencesState {
  preferences: Preferences;
  /** Takes effect at once; stored in the app's settings (never in the library). */
  change(change: Partial<Preferences>): void;
}

const Context = createContext<PreferencesState | null>(null);

/** 设置 as the page sees them: what the settings panel, the list's “…” menu and the look all read and change. */
export function usePreferences(): PreferencesState {
  const state = useContext(Context);
  if (!state) throw new Error("usePreferences outside PreferencesProvider");
  return state;
}

export function PreferencesProvider({ children }: { children(preferences: Preferences): ReactNode }) {
  const [preferences, setPreferences] = useState(window.notes.preferences);
  // The look the page draws itself; light or dark is the main process's (nativeTheme).
  useAccent(preferences.accent);
  const change = (change: Partial<Preferences>) => {
    setPreferences((now) => ({ ...now, ...change }));
    void window.notes.setPreferences(change);
  };
  return <Context.Provider value={{ preferences, change }}>{children(preferences)}</Context.Provider>;
}
