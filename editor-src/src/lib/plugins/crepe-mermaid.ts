import { renderMermaidCached } from "./mermaid";
import type { EditorView } from "@milkdown/kit/prose/view";

const RENDERED_ATTR = "data-mermaid-rendered";

/**
 * Scan the ProseMirror document for code_block nodes with language "mermaid"
 * and replace their DOM representation with rendered SVG diagrams.
 *
 * Works with Milkdown Crepe which renders code blocks via CodeMirror
 * (not <pre><code> elements).
 */
async function renderMermaidBlocks(view: EditorView, container: HTMLElement): Promise<void> {
  const doc = view.state.doc;
  const positions: { pos: number; text: string }[] = [];

  // Walk the document to find code_block nodes with language "mermaid"
  doc.descendants((node, pos) => {
    if (node.type.name === "code_block" && node.attrs?.language === "mermaid") {
      const text = node.textContent;
      if (text.trim()) {
        positions.push({ pos, text });
      }
    }
  });

  for (const { pos, text } of positions) {
    // Get the DOM node for this ProseMirror position
    const domNode = view.nodeDOM(pos);
    if (!domNode || !(domNode instanceof HTMLElement)) continue;
    if (domNode.hasAttribute(RENDERED_ATTR)) continue;

    const { svg, error } = await renderMermaidCached(text);

    const wrapper = document.createElement("div");
    wrapper.className = "mermaid-rendered-wrapper";
    wrapper.setAttribute(RENDERED_ATTR, "true");
    wrapper.style.cssText = [
      "cursor: pointer",
      "padding: 1rem",
      "border-radius: 6px",
      "background: var(--crepe-color-surface, var(--bg-primary, #1e1e2e))",
      "border: 1px solid var(--crepe-color-line, var(--border-color, #313244))",
      "margin: 0.5rem 0",
      "text-align: center",
    ].join(";");

    if (error || !svg) {
      wrapper.innerHTML = `<pre style="color:#f38ba8;white-space:pre-wrap;text-align:left;font-size:0.85em">[Mermaid error] ${escapeHtml(error ?? "Unknown error")}</pre>`;
    } else {
      wrapper.innerHTML = svg;
      const svgEl = wrapper.querySelector("svg");
      if (svgEl) {
        svgEl.style.maxWidth = "100%";
        svgEl.style.height = "auto";
      }
    }

    // Click toggles back to code view
    wrapper.addEventListener("click", () => {
      wrapper.replaceWith(domNode);
      domNode.removeAttribute(RENDERED_ATTR);
    });

    // Replace the CodeMirror editor DOM with the rendered diagram
    domNode.setAttribute(RENDERED_ATTR, "true");
    domNode.replaceWith(wrapper);
  }
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Set up mermaid rendering for a Crepe editor tab.
 * Uses the ProseMirror EditorView to find code blocks, not DOM scanning.
 *
 * @param container The editor tab container element
 * @param getView Function that returns the current EditorView (may change on re-create)
 * @returns A cleanup function
 */
export function setupMermaidObserver(
  container: HTMLElement,
  getView?: () => EditorView | null
): () => void {
  let suppressed = false;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  function scanAndRender(): void {
    if (suppressed) return;
    const view = getView?.();
    if (!view) return;
    renderMermaidBlocks(view, container);
  }

  // Initial scan after a short delay (let Crepe finish rendering)
  setTimeout(scanAndRender, 300);

  const observer = new MutationObserver(() => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(scanAndRender, 500);
  });

  observer.observe(container, {
    childList: true,
    subtree: true,
  });

  return () => {
    observer.disconnect();
    if (debounceTimer) clearTimeout(debounceTimer);
  };
}
