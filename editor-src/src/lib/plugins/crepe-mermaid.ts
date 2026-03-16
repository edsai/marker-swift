import { renderMermaidCached } from "./mermaid";

const RENDERED_ATTR = "data-mermaid-rendered";

/**
 * Replace a <pre><code class="language-mermaid"> block with a rendered SVG wrapper.
 * Attaches a click handler to toggle back to code view.
 */
async function processCodeBlock(pre: HTMLPreElement, onToggleBack?: () => void): Promise<void> {
  // Guard against double-processing
  if (pre.hasAttribute(RENDERED_ATTR)) return;
  pre.setAttribute(RENDERED_ATTR, "true");

  const code = pre.querySelector("code.language-mermaid");
  if (!code) return;

  const source = code.textContent ?? "";
  if (!source.trim()) return;

  const { svg, error } = await renderMermaidCached(source);

  const wrapper = document.createElement("div");
  wrapper.className = "mermaid-rendered-wrapper";
  wrapper.style.cssText = [
    "cursor: pointer",
    "padding: 1rem",
    "border-radius: 6px",
    "background: var(--crepe-color-surface, #1e1e2e)",
    "border: 1px solid var(--crepe-color-line, #313244)",
    "margin: 0.5rem 0",
    "text-align: center",
  ].join(";");

  if (error || !svg) {
    wrapper.innerHTML = `<pre style="color:#f38ba8;white-space:pre-wrap;text-align:left;font-size:0.85em">[Mermaid error] ${escapeHtml(error ?? "Unknown error")}</pre>`;
  } else {
    wrapper.innerHTML = svg;
    // Make inline SVGs responsive and theme-friendly
    const svgEl = wrapper.querySelector("svg");
    if (svgEl) {
      svgEl.style.maxWidth = "100%";
      svgEl.style.height = "auto";
    }
  }

  // Click toggles back to code view
  wrapper.addEventListener("click", () => {
    if (onToggleBack) onToggleBack();
    pre.removeAttribute(RENDERED_ATTR);
    wrapper.replaceWith(pre);
  });

  pre.replaceWith(wrapper);
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Set up a MutationObserver on the given container to detect mermaid code blocks
 * and replace them with rendered SVG diagrams.
 *
 * @returns A cleanup function that disconnects the observer.
 */
export function setupMermaidObserver(container: HTMLElement): () => void {
  let suppressed = false;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  function scanAndRender(): void {
    if (suppressed) return;
    const blocks = container.querySelectorAll<HTMLPreElement>(
      `pre:not([${RENDERED_ATTR}]) > code.language-mermaid`
    );
    blocks.forEach((code) => {
      const pre = code.parentElement as HTMLPreElement;
      processCodeBlock(pre, () => {
        // Suppress observer while toggling back to code view
        suppressed = true;
        setTimeout(() => { suppressed = false; }, 300);
      });
    });
  }

  // Run an initial scan in case content is already present
  scanAndRender();

  const observer = new MutationObserver(() => {
    // Debounce to avoid excessive scans during typing
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(scanAndRender, 200);
  });

  observer.observe(container, {
    childList: true,
    subtree: true,
  });

  return () => {
    observer.disconnect();
  };
}
