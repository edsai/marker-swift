import mermaid from "mermaid";

// Initialize mermaid with dark theme
mermaid.initialize({
  startOnLoad: false,
  theme: "dark",
  securityLevel: "strict",
});

let renderCounter = 0;

/**
 * Render a Mermaid diagram string into an SVG string.
 * Returns the SVG markup or an error message.
 */
export async function renderMermaid(code: string): Promise<{ svg: string; error: string | null }> {
  const id = `mermaid-${++renderCounter}`;
  try {
    const { svg } = await mermaid.render(id, code.trim());
    return { svg, error: null };
  } catch (e) {
    const errorMsg = e instanceof Error ? e.message : String(e);
    return {
      svg: "",
      error: errorMsg,
    };
  }
}

/**
 * Cache for rendered Mermaid SVGs keyed by content hash.
 */
const svgCache = new Map<string, string>();

function simpleHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0;
  }
  return hash.toString(36);
}

/**
 * Render with caching. Returns cached SVG if the code hasn't changed.
 */
export async function renderMermaidCached(code: string): Promise<{ svg: string; error: string | null }> {
  const key = code.trim();
  const cached = svgCache.get(key);
  if (cached) {
    return { svg: cached, error: null };
  }

  // Cap cache at 50 entries
  if (svgCache.size >= 50) {
    const firstKey = svgCache.keys().next().value;
    if (firstKey !== undefined) svgCache.delete(firstKey);
  }

  const result = await renderMermaid(code);
  if (result.svg) {
    svgCache.set(key, result.svg);
  }
  return result;
}
