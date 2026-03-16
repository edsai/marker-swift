import { Crepe } from "@milkdown/crepe";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame-dark.css";
import { editorViewCtx, prosePluginsCtx } from "@milkdown/kit/core";
import type { EditorView } from "@milkdown/kit/prose/view";
import { setupMermaidObserver } from "../plugins/crepe-mermaid";
import { createSearchPlugin } from "../plugins/search";

export interface TabState {
  id: string;
  filePath: string | null;
  markdown: string;
  dirty: boolean;
  scrollTop: number;
  cursorPos: number;
  encoding: string;
  lineEnding: "lf" | "crlf";
}

interface PoolEntry {
  tabId: string;
  crepe: Crepe;
  container: HTMLDivElement;
  lastAccessed: number;
  cleanupMermaid: () => void;
}

const MAX_POOL_SIZE = 5;

// Keep legacy type exports for backwards compatibility
export type EvictionCallback = (tabId: string, markdown: string) => void;
export type ChangeCallback = (tabId: string) => void;

export interface TabPoolCallbacks {
  onEvict?: (tabId: string, markdown: string) => void;
  onChange?: (tabId: string) => void;
  onCursorChange?: (tabId: string, line: number, col: number) => void;
  onImagePaste?: (tabId: string, base64: string, extension: string) => void;
}

export class TabPool {
  private entries: Map<string, PoolEntry> = new Map();
  private hostEl: HTMLElement;
  private activeTabId: string | null = null;
  private callbacks: TabPoolCallbacks;

  constructor(hostEl: HTMLElement, callbacks?: TabPoolCallbacks) {
    this.hostEl = hostEl;
    this.callbacks = callbacks ?? {};
  }

  async show(tabId: string, markdown: string): Promise<Crepe> {
    // Hide current active tab
    if (this.activeTabId && this.activeTabId !== tabId) {
      const current = this.entries.get(this.activeTabId);
      if (current) {
        current.container.style.display = "none";
      }
    }

    // Check if tab already has a cached instance
    const existing = this.entries.get(tabId);
    if (existing) {
      existing.container.style.display = "block";
      existing.lastAccessed = Date.now();
      this.activeTabId = tabId;
      return existing.crepe;
    }

    // Need to create a new instance — evict LRU if at capacity
    if (this.entries.size >= MAX_POOL_SIZE) {
      await this.evictLRU();
    }

    // Create new container and Crepe instance
    const container = document.createElement("div");
    container.className = "editor-tab-container";
    container.style.display = "block";
    container.style.height = "100%";
    container.style.overflowY = "auto";
    this.hostEl.appendChild(container);

    const crepe = new Crepe({
      root: container,
      defaultValue: markdown,
    });

    // Register the search decoration plugin before the editor is created
    crepe.editor.config((ctx) => {
      ctx.update(prosePluginsCtx, (plugins) => [...plugins, createSearchPlugin()]);
    });

    await crepe.create();

    // Set up Mermaid diagram rendering observer
    // Pass a getView function so the observer can access the EditorView
    const getView = () => {
      try {
        return crepe.editor.ctx.get(editorViewCtx);
      } catch {
        return null;
      }
    };
    const cleanupMermaid = setupMermaidObserver(container, getView);

    // Listen for content changes to mark tab dirty
    if (this.callbacks.onChange) {
      const cb = this.callbacks.onChange;
      const tid = tabId;
      container.addEventListener("input", () => cb(tid));
    }

    // Listen for cursor position changes
    if (this.callbacks.onCursorChange) {
      const onCursorChange = this.callbacks.onCursorChange;
      const tid = tabId;
      let debounceTimer: ReturnType<typeof setTimeout> | null = null;

      const readCursor = () => {
        if (debounceTimer !== null) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          debounceTimer = null;
          const proseMirrorEl = container.querySelector(".ProseMirror") as HTMLElement | null;
          if (!proseMirrorEl) return;

          // Try to read position from ProseMirror EditorView attached to the DOM node
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const pmView = (proseMirrorEl as any).pmViewDesc?.view;
          if (pmView && pmView.state) {
            const { state } = pmView;
            const pos = state.selection.from;
            const text: string = state.doc.textBetween(0, pos, "\n");
            const lines = text.split("\n");
            onCursorChange(tid, lines.length, lines[lines.length - 1].length + 1);
            return;
          }

          // Fallback: derive line/col from the DOM selection within the editor
          const sel = window.getSelection();
          if (!sel || sel.rangeCount === 0) return;
          const range = sel.getRangeAt(0);
          if (!proseMirrorEl.contains(range.startContainer)) return;
          const priorRange = document.createRange();
          priorRange.setStart(proseMirrorEl, 0);
          priorRange.setEnd(range.startContainer, range.startOffset);
          const text = priorRange.toString();
          const lines = text.split("\n");
          onCursorChange(tid, lines.length, lines[lines.length - 1].length + 1);
        }, 100);
      };

      container.addEventListener("mouseup", readCursor);
      container.addEventListener("keyup", readCursor);
    }

    // Image paste handler
    container.addEventListener("paste", (e: ClipboardEvent) => {
      if (!this.callbacks.onImagePaste) return;
      const items = e.clipboardData?.items;
      if (!items) return;

      for (const item of Array.from(items)) {
        if (item.type.startsWith("image/")) {
          e.preventDefault();
          const blob = item.getAsFile();
          if (!blob) continue;
          const extension = item.type.split("/")[1] || "png";
          const reader = new FileReader();
          reader.onload = () => {
            const base64 = (reader.result as string).split(",")[1];
            this.callbacks.onImagePaste!(tabId, base64, extension);
          };
          reader.readAsDataURL(blob);
          break;
        }
      }
    });

    // Image drop handler
    container.addEventListener("dragover", (e: DragEvent) => {
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
    });

    container.addEventListener("drop", (e: DragEvent) => {
      if (!this.callbacks.onImagePaste) return;
      const files = e.dataTransfer?.files;
      if (!files || files.length === 0) return;

      const file = files[0];
      if (!file.type.startsWith("image/")) return;

      e.preventDefault();
      const extension = file.name.split(".").pop() || "png";
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = (reader.result as string).split(",")[1];
        this.callbacks.onImagePaste!(tabId, base64, extension);
      };
      reader.readAsDataURL(file);
    });

    const entry: PoolEntry = {
      tabId,
      crepe,
      container,
      lastAccessed: Date.now(),
      cleanupMermaid,
    };

    this.entries.set(tabId, entry);
    this.activeTabId = tabId;

    return crepe;
  }

  hide(tabId: string): void {
    const entry = this.entries.get(tabId);
    if (entry) {
      entry.container.style.display = "none";
    }
    if (this.activeTabId === tabId) {
      this.activeTabId = null;
    }
  }

  getMarkdown(tabId: string): string | null {
    const entry = this.entries.get(tabId);
    if (!entry) return null;
    return entry.crepe.getMarkdown();
  }

  getCrepe(tabId: string): Crepe | null {
    return this.entries.get(tabId)?.crepe ?? null;
  }

  /**
   * Get the ProseMirror EditorView for a given tab.
   * Returns null if the tab is not loaded or the view is not available.
   */
  getEditorView(tabId: string): EditorView | null {
    const entry = this.entries.get(tabId);
    if (!entry) return null;
    try {
      return entry.crepe.editor.ctx.get(editorViewCtx);
    } catch {
      return null;
    }
  }

  has(tabId: string): boolean {
    return this.entries.has(tabId);
  }

  private async evictLRU(): Promise<string | null> {
    let oldest: PoolEntry | null = null;
    for (const entry of this.entries.values()) {
      // Never evict the active tab
      if (entry.tabId === this.activeTabId) continue;
      if (!oldest || entry.lastAccessed < oldest.lastAccessed) {
        oldest = entry;
      }
    }

    if (!oldest) return null;

    const evictedId = oldest.tabId;
    // Sync markdown before destroying so content is not lost
    const markdown = oldest.crepe.getMarkdown();
    if (this.callbacks.onEvict) {
      this.callbacks.onEvict(evictedId, markdown);
    }
    oldest.cleanupMermaid();
    await oldest.crepe.destroy();
    oldest.container.remove();
    this.entries.delete(evictedId);

    return evictedId;
  }

  async destroyTab(tabId: string): Promise<void> {
    const entry = this.entries.get(tabId);
    if (entry) {
      entry.cleanupMermaid();
      await entry.crepe.destroy();
      entry.container.remove();
      this.entries.delete(tabId);
    }
    if (this.activeTabId === tabId) {
      this.activeTabId = null;
    }
  }

  async destroyAll(): Promise<void> {
    for (const entry of this.entries.values()) {
      entry.cleanupMermaid();
      await entry.crepe.destroy();
      entry.container.remove();
    }
    this.entries.clear();
    this.activeTabId = null;
  }

  scrollToHeading(tabId: string, headingIndex: number): void {
    const entry = this.entries.get(tabId);
    if (!entry) return;

    const headings = entry.container.querySelectorAll("h1, h2, h3, h4, h5, h6");
    if (headingIndex < 0 || headingIndex >= headings.length) return;

    const heading = headings[headingIndex] as HTMLElement;
    heading.scrollIntoView({ behavior: "smooth", block: "start" });

    // Offset so heading isn't flush against the top
    setTimeout(() => {
      entry.container.scrollTop = Math.max(0, entry.container.scrollTop - 20);
    }, 300);
  }
}
