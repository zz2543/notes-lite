import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import type { Preferences } from "../../shared/preferences";
import { useAccent, useSpaceThemeChrome, useTypography } from "./appearance";

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
  useTypography(preferences.typography);
  useSpaceThemeChrome(preferences.spaceTheme, preferences.customSpaceTheme);
  // Changed in the other window (设置, or the main one): shown here at once.
  useEffect(() => window.notes.onPreferencesChanged(setPreferences), []);
  const change = (change: Partial<Preferences>) => {
    setPreferences((now) => ({ ...now, ...change }));
    // What the main process kept, other windows' changes included: the other window is not told of this one.
    void window.notes.setPreferences(change).then(setPreferences);
  };
  return <Context.Provider value={{ preferences, change }}>{children(preferences)}</Context.Provider>;
}
