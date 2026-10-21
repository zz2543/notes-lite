import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { SettingsWindow } from "./SettingsPanel";
import { applyAppearance } from "./appearance";
import { MotionProvider } from "./MotionProvider";
import { PreferencesProvider } from "./preferences";
import "./fonts";
import "./tokens.css";
import "./styles.css";

// macOS draws its window buttons over the title bar; what sits beside them makes room.
document.documentElement.classList.toggle("mac", /Mac/.test(navigator.platform));

applyAppearance(window.notes.appearance);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PreferencesProvider>
      {(preferences) => (
        <MotionProvider intensity={preferences.motion}>
          {/* The 设置 window loads the same page, at #settings. */}
          {location.hash === "#settings" ? <SettingsWindow /> : <App />}
        </MotionProvider>
      )}
    </PreferencesProvider>
  </StrictMode>,
);
