import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { applyAppearance } from "./appearance";
import { MotionProvider } from "./MotionProvider";
import { PreferencesProvider } from "./preferences";
import "./fonts";
import "./tokens.css";
import "./styles.css";

applyAppearance(window.notes.appearance);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PreferencesProvider>
      {(preferences) => (
        <MotionProvider intensity={preferences.motion}>
          <App />
        </MotionProvider>
      )}
    </PreferencesProvider>
  </StrictMode>,
);
