/// <reference types="vite/client" />
import type { NotesApi } from "../../shared/api";

declare global {
  interface Window {
    notes: NotesApi;
  }
}
