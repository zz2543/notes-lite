/// <reference types="vite/client" />
import type { NotesApi } from "../../shared/api";

declare global {
  interface Window {
    notes: NotesApi;
  }
}

// mhchem adds \ce and \pu to the KaTeX it imports; it exports nothing.
declare module "katex/contrib/mhchem";
