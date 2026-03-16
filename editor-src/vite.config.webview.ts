import { defineConfig } from "vite";

export default defineConfig({
  build: {
    outDir: "dist-editor",
    rollupOptions: {
      input: "src/lib/editor/webview-entry.ts",
      output: {
        entryFileNames: "editor.js",
        format: "iife",
      },
    },
    cssCodeSplit: false,
  },
});
