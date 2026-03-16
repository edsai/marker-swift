// Pure ProseMirror search — no Tauri, no Svelte imports
import { EditorView, Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import { Plugin, PluginKey } from "@milkdown/kit/prose/state";

export interface FindOptions {
  caseSensitive: boolean;
  wholeWord: boolean;
  regex: boolean;
}

export interface SearchState {
  matches: { from: number; to: number }[];
  currentIndex: number;
  count: number;
}

// PluginKey for managing search decorations
const searchPluginKey = new PluginKey<DecorationSet>("search");

// Build a regex from the query and options
function buildRegex(query: string, options: FindOptions): RegExp | null {
  if (!query) return null;
  try {
    let pattern = options.regex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (options.wholeWord) {
      pattern = `\\b${pattern}\\b`;
    }
    const flags = options.caseSensitive ? "g" : "gi";
    return new RegExp(pattern, flags);
  } catch {
    return null;
  }
}

// Collect all text positions in the doc by walking nodes
function collectMatches(
  view: EditorView,
  query: string,
  options: FindOptions
): { from: number; to: number }[] {
  const matches: { from: number; to: number }[] = [];
  const regex = buildRegex(query, options);
  if (!regex) return matches;

  const doc = view.state.doc;
  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return;
    regex.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(node.text)) !== null) {
      const from = pos + match.index;
      const to = from + match[0].length;
      matches.push({ from, to });
    }
  });
  return matches;
}

// Apply decorations to the view for the current search state
function applyDecorations(view: EditorView, state: SearchState): void {
  const { matches, currentIndex } = state;
  const decos: Decoration[] = matches.map((m, i) => {
    const cls = i === currentIndex ? "search-current" : "search-highlight";
    return Decoration.inline(m.from, m.to, { class: cls });
  });
  const decoSet = DecorationSet.create(view.state.doc, decos);

  // Dispatch a meta transaction to store decorations in plugin state
  const tr = view.state.tr.setMeta(searchPluginKey, decoSet);
  view.dispatch(tr);
}

// Scroll the current match into view
function scrollToCurrentMatch(view: EditorView, state: SearchState): void {
  if (state.matches.length === 0) return;
  const match = state.matches[state.currentIndex];
  if (!match) return;
  // Use DOM scrollIntoView on the node at the match position
  try {
    const domNode = view.domAtPos(match.from);
    if (domNode && domNode.node) {
      const el = domNode.node instanceof Element
        ? domNode.node
        : domNode.node.parentElement;
      el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    }
  } catch {
    // domAtPos can throw for out-of-bounds positions — safe to ignore
  }
}

/**
 * Search the doc for query and highlight all matches.
 * Returns a SearchState with match positions and count.
 */
export function findInDoc(
  view: EditorView,
  query: string,
  options: FindOptions
): SearchState {
  const matches = collectMatches(view, query, options);
  const state: SearchState = {
    matches,
    currentIndex: matches.length > 0 ? 0 : -1,
    count: matches.length,
  };
  applyDecorations(view, state);
  if (matches.length > 0) {
    scrollToCurrentMatch(view, state);
  }
  return state;
}

/**
 * Move to the next match, wrapping around.
 */
export function nextMatch(view: EditorView, state: SearchState): SearchState {
  if (state.matches.length === 0) return state;
  const nextIndex = (state.currentIndex + 1) % state.matches.length;
  const next: SearchState = { ...state, currentIndex: nextIndex };
  applyDecorations(view, next);
  scrollToCurrentMatch(view, next);
  return next;
}

/**
 * Move to the previous match, wrapping around.
 */
export function prevMatch(view: EditorView, state: SearchState): SearchState {
  if (state.matches.length === 0) return state;
  const prevIndex =
    (state.currentIndex - 1 + state.matches.length) % state.matches.length;
  const prev: SearchState = { ...state, currentIndex: prevIndex };
  applyDecorations(view, prev);
  scrollToCurrentMatch(view, prev);
  return prev;
}

/**
 * Replace the current match with the replacement string.
 * Returns updated SearchState after replacement, preserving the current index
 * (clamped to the new match count). Callers should pass query/options so that
 * the match list can be refreshed; if omitted the decorations are cleared.
 */
export function replaceMatch(
  view: EditorView,
  state: SearchState,
  replacement: string,
  query?: string,
  options?: FindOptions
): SearchState {
  if (state.matches.length === 0 || state.currentIndex < 0) return state;
  const match = state.matches[state.currentIndex];
  if (!match) return state;

  const tr = view.state.tr.replaceWith(
    match.from,
    match.to,
    view.state.schema.text(replacement)
  );
  view.dispatch(tr);

  // If query is provided, refresh match list and preserve index position
  if (query !== undefined && options !== undefined) {
    const newMatches = collectMatches(view, query, options);
    // Clamp current index — after replacing, total count drops by one, so
    // wrapping keeps the cursor on the "next" match naturally.
    const newIndex = newMatches.length === 0
      ? -1
      : Math.min(state.currentIndex, newMatches.length - 1);
    const newState: SearchState = {
      matches: newMatches,
      currentIndex: newIndex,
      count: newMatches.length,
    };
    applyDecorations(view, newState);
    if (newMatches.length > 0) scrollToCurrentMatch(view, newState);
    return newState;
  }

  // Fallback: caller will call findInDoc to refresh — preserve index hint via count
  const cleared: SearchState = {
    matches: [],
    currentIndex: state.currentIndex,
    count: 0,
  };
  return cleared;
}

/**
 * Replace all matches with the replacement string.
 * Returns the number of replacements made.
 */
export function replaceAll(
  view: EditorView,
  query: string,
  options: FindOptions,
  replacement: string
): number {
  const matches = collectMatches(view, query, options);
  if (matches.length === 0) return 0;

  // Apply replacements in reverse order to preserve positions
  let tr = view.state.tr;
  for (let i = matches.length - 1; i >= 0; i--) {
    const m = matches[i];
    tr = tr.replaceWith(m.from, m.to, view.state.schema.text(replacement));
  }
  view.dispatch(tr);

  // Clear decorations after replace all
  const emptySet = DecorationSet.empty;
  const clearTr = view.state.tr.setMeta(searchPluginKey, emptySet);
  view.dispatch(clearTr);

  return matches.length;
}

/**
 * Remove all search highlight decorations from the view.
 */
export function clearHighlights(view: EditorView): void {
  const emptySet = DecorationSet.empty;
  const tr = view.state.tr.setMeta(searchPluginKey, emptySet);
  view.dispatch(tr);
}

/**
 * Create a ProseMirror Plugin that manages search decorations.
 * This plugin must be added to the editor's state for decorations to render.
 * When using Milkdown/Crepe, decorations are applied directly via dispatch —
 * the plugin stores the current DecorationSet in state so ProseMirror can render them.
 */
export function createSearchPlugin(): Plugin {
  return new Plugin({
    key: searchPluginKey,
    state: {
      init() {
        return DecorationSet.empty;
      },
      apply(tr, oldSet, _oldState, newState) {
        const meta = tr.getMeta(searchPluginKey);
        if (meta !== undefined) {
          return meta as DecorationSet;
        }
        // Map decorations through document changes
        return oldSet.map(tr.mapping, newState.doc);
      },
    },
    props: {
      decorations(state) {
        return searchPluginKey.getState(state) ?? DecorationSet.empty;
      },
    },
  });
}
