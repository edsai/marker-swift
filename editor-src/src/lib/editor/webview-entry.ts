import { TabPool } from "./TabPool";
import type { TabPoolCallbacks } from "./TabPool";
import { findInDoc, nextMatch, prevMatch, replaceMatch, replaceAll, clearHighlights } from "../plugins/search";
import type { FindOptions, SearchState } from "../plugins/search";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame-dark.css";

// The editor host element
let pool: TabPool | null = null;

// Search state per tab
const searchStates = new Map<string, SearchState>();

// Bridge: Swift calls these via evaluateJavaScript
const marker = {
  async init() {
    const hostEl = document.getElementById("editor-host")!;
    pool = new TabPool(hostEl, {
      onEvict: (tabId, markdown) => {
        postToSwift({ type: "evicted", tabId, markdown });
      },
      onChange: (tabId) => {
        postToSwift({ type: "dirty", tabId, isDirty: true });
      },
      onCursorChange: (tabId, line, col) => {
        postToSwift({ type: "cursorChanged", tabId, line, col });
      },
      onImagePaste: (tabId, base64, extension) => {
        postToSwift({ type: "imagePaste", tabId, base64, extension });
      },
    });

    // Open a welcome tab so the editor is visible immediately
    await pool.show("welcome", "# Welcome to Marker\n\nStart typing or open a file.");
    postToSwift({ type: "ready" });
  },

  async openTab(tabId: string, markdown: string) {
    if (!pool) return;
    await pool.show(tabId, markdown);
  },

  async switchTab(tabId: string, markdown: string) {
    if (!pool) return;
    await pool.show(tabId, markdown);
  },

  getMarkdown(tabId: string): string | null {
    if (!pool) return null;
    return pool.getMarkdown(tabId);
  },

  async requestMarkdown(tabId: string) {
    const md = pool?.getMarkdown(tabId) ?? null;
    postToSwift({ type: "markdown", tabId, content: md });
  },

  async closeTab(tabId: string) {
    if (!pool) return;
    await pool.destroyTab(tabId);
  },

  scrollToHeading(tabId: string, index: number) {
    pool?.scrollToHeading(tabId, index);
  },

  setTheme(theme: "dark" | "light") {
    document.documentElement.setAttribute("data-theme", theme);
  },

  setFontSize(px: number) {
    document.documentElement.style.setProperty("--editor-font-size", `${px}px`);
  },

  setFontFamily(family: string) {
    document.documentElement.style.setProperty("--editor-font-family", family);
  },

  find(tabId: string, query: string, caseSensitive: boolean, wholeWord: boolean, useRegex: boolean) {
    if (!pool) return null;
    const view = pool.getEditorView(tabId);
    if (!view) return null;
    const options: FindOptions = { caseSensitive, wholeWord, regex: useRegex };
    const state = findInDoc(view, query, options);
    searchStates.set(tabId, state);
    return { count: state.count, currentIndex: state.currentIndex };
  },

  findNext(tabId: string) {
    if (!pool) return null;
    const view = pool.getEditorView(tabId);
    const state = searchStates.get(tabId);
    if (!view || !state) return null;
    const next = nextMatch(view, state);
    searchStates.set(tabId, next);
    return { count: next.count, currentIndex: next.currentIndex };
  },

  findPrev(tabId: string) {
    if (!pool) return null;
    const view = pool.getEditorView(tabId);
    const state = searchStates.get(tabId);
    if (!view || !state) return null;
    const prev = prevMatch(view, state);
    searchStates.set(tabId, prev);
    return { count: prev.count, currentIndex: prev.currentIndex };
  },

  replaceOne(tabId: string, replacement: string, query: string, caseSensitive: boolean, wholeWord: boolean, useRegex: boolean) {
    if (!pool) return null;
    const view = pool.getEditorView(tabId);
    const state = searchStates.get(tabId);
    if (!view || !state) return null;
    const options: FindOptions = { caseSensitive, wholeWord, regex: useRegex };
    const updated = replaceMatch(view, state, replacement, query, options);
    searchStates.set(tabId, updated);
    return { count: updated.count, currentIndex: updated.currentIndex };
  },

  replaceAllMatches(tabId: string, query: string, replacement: string, caseSensitive: boolean, wholeWord: boolean, useRegex: boolean) {
    if (!pool) return 0;
    const view = pool.getEditorView(tabId);
    if (!view) return 0;
    const options: FindOptions = { caseSensitive, wholeWord, regex: useRegex };
    const count = replaceAll(view, query, options, replacement);
    searchStates.delete(tabId);
    return count;
  },

  clearSearch(tabId: string) {
    if (!pool) return;
    const view = pool.getEditorView(tabId);
    if (view) clearHighlights(view);
    searchStates.delete(tabId);
  },

  insertText(tabId: string, text: string) {
    if (!pool) return;
    const view = pool.getEditorView(tabId);
    if (!view) return;
    const { from } = view.state.selection;
    const tr = view.state.tr.insertText(text, from);
    view.dispatch(tr);
  },
};

function postToSwift(message: Record<string, unknown>) {
  try {
    (window as any).webkit?.messageHandlers?.marker?.postMessage(message);
  } catch (e) {
    console.error("Failed to post to Swift:", e);
  }
}

// Expose globally
(window as any).marker = marker;
