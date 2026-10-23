/** space.load("react")'s script, bundled at build time (electron.vite.config.ts, spaceReact). */
declare module "virtual:space-react" {
  const script: string;
  export default script;
}
