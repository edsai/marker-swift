import { Plugin, PluginKey } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import type { EditorView } from "@milkdown/kit/prose/view";
import { renderMermaidCached } from "./mermaid";

const mermaidPluginKey = new PluginKey<DecorationSet>("mermaid-diagrams");

/**
 * ProseMirror plugin that renders mermaid code blocks as SVG diagrams.
 * Uses Widget decorations so ProseMirror's document model is never modified.
 * The code block stays in the doc; the SVG is rendered as a decoration after it.
 */
export function createMermaidPlugin(): Plugin {
  let rendering = false;

  async function buildDecorations(view: EditorView): Promise<DecorationSet> {
    const doc = view.state.doc;
    const decorations: Decoration[] = [];

    const mermaidBlocks: { pos: number; end: number; text: string }[] = [];

    doc.descendants((node, pos) => {
      if (node.type.name === "code_block" && node.attrs?.language === "mermaid") {
        const text = node.textContent.trim();
        if (text) {
          mermaidBlocks.push({ pos, end: pos + node.nodeSize, text });
        }
      }
    });

    for (const block of mermaidBlocks) {
      const { svg, error } = await renderMermaidCached(block.text);

      // Widget decoration placed after the code block
      const widget = Decoration.widget(block.end, () => {
        const wrapper = document.createElement("div");
        wrapper.className = "mermaid-rendered";
        wrapper.style.cssText = [
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
        return wrapper;
      }, { side: 1 });

      decorations.push(widget);

      // Also hide the code block itself using a node decoration
      decorations.push(
        Decoration.node(block.pos, block.end, {
          class: "mermaid-source-hidden",
          style: "display: none",
        })
      );
    }

    return DecorationSet.create(doc, decorations);
  }

  return new Plugin({
    key: mermaidPluginKey,
    state: {
      init() {
        return DecorationSet.empty;
      },
      apply(tr, oldSet) {
        const meta = tr.getMeta(mermaidPluginKey);
        if (meta !== undefined) {
          return meta as DecorationSet;
        }
        if (tr.docChanged) {
          return oldSet.map(tr.mapping, tr.doc);
        }
        return oldSet;
      },
    },
    props: {
      decorations(state) {
        return mermaidPluginKey.getState(state) ?? DecorationSet.empty;
      },
    },
    view(editorView) {
      // Render mermaid blocks after the view is created
      const renderAll = () => {
        if (rendering) return;
        rendering = true;
        buildDecorations(editorView).then((decoSet) => {
          rendering = false;
          const tr = editorView.state.tr.setMeta(mermaidPluginKey, decoSet);
          editorView.dispatch(tr);
        });
      };

      // Initial render with a delay to let Crepe finish setup
      setTimeout(renderAll, 500);

      return {
        update(view, prevState) {
          if (view.state.doc !== prevState.doc) {
            // Debounce re-renders on doc changes
            setTimeout(renderAll, 800);
          }
        },
      };
    },
  });
}

/**
 * Legacy API — kept for backward compatibility with TabPool.
 * Now returns a no-op cleanup since rendering is handled by the ProseMirror plugin.
 */
export function setupMermaidObserver(
  _container: HTMLElement,
  _getView?: () => EditorView | null
): () => void {
  // Mermaid rendering is now handled by createMermaidPlugin()
  return () => {};
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
