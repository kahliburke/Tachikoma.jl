/**
 * tachi-examples.ts — VitePress markdown-it plugin for Tachikoma example rendering
 *
 * Finds tachi annotations in two forms:
 *   1. Raw HTML comments: <!-- tachi:widget gauge_basic w=50 h=3 -->
 *   2. Documenter-escaped: &lt;!– tachi:widget gauge_basic w=50 h=3 –&gt;
 *
 * Single-pass core rule: builds a new token array, skipping annotations and
 * injecting <img> blocks after the corresponding code fence.
 */

import type MarkdownIt from 'markdown-it'

interface TachiAnnotation {
  kind: 'widget' | 'app'
  id: string
  w: number       // terminal columns
  h: number       // terminal rows
  frames: number
  chrome: boolean
}

// 1x cell dimensions (pixels per terminal cell) — must match generate_assets.jl defaults
const CELL_W = 10
const CELL_H = 20

// Match raw HTML comment (single-line and multi-line via [\s\S])
const RAW_RE = /<!--\s*tachi:(widget|app)\s+(\S+)([\s\S]*?)-->/
// Match Documenter-escaped form (HTML entities + en-dash)
const ESCAPED_RE = /&lt;![\u2013-]\s*tachi:(widget|app)\s+(\S+)([\s\S]*?)[\u2013-]&gt;/

// Match tachi:noeval annotations (raw and escaped forms) — stripped from output
const NOEVAL_RAW_RE = /<!--\s*tachi:noeval\s*-->/
const NOEVAL_ESCAPED_RE = /&lt;![\u2013-]\s*tachi:noeval\s*[\u2013-]&gt;/

function parseAnnotation(text: string): TachiAnnotation | null {
  const m = text.match(RAW_RE) || text.match(ESCAPED_RE)
  if (!m) return null

  const kind = m[1] as 'widget' | 'app'
  const id = m[2]
  const body = m[3] || ''

  // For multi-line comments, only parse params from the first line
  const paramStr = body.includes('\n') ? body.split('\n')[0] : body

  const params: Record<string, string> = {}
  for (const tok of paramStr.trim().split(/\s+/)) {
    if (!tok) continue
    if (tok.includes('=')) {
      const [k, v] = tok.split('=', 2)
      params[k] = v
    } else {
      params[tok] = 'true'
    }
  }

  return {
    kind,
    id,
    w: parseInt(params['w'] || (kind === 'widget' ? '60' : '80'), 10),
    h: parseInt(params['h'] || (kind === 'widget' ? '5' : '24'), 10),
    frames: parseInt(params['frames'] || (kind === 'widget' ? '1' : '120'), 10),
    chrome: params['chrome'] === 'true',
  }
}

function makeImageHtml(ann: TachiAnnotation, base: string): string {
  const ext = 'gif'
  // Release URLs are flat (no subdirs); local dev has assets/examples/
  const path = base.startsWith('http') ? `${base}${ann.id}.${ext}` : `${base}examples/${ann.id}.${ext}`
  const alt = `${ann.id} example`
  // Display at 1x CSS dimensions; the 2x retina GIF provides crisp rendering
  const cssWidth = ann.w * CELL_W

  if (ann.chrome) {
    return (
      `<div class="tachi-example-container">\n` +
      `<TerminalWindow title="${ann.id.replace(/_/g, ' ')}">\n` +
      `<img src="${path}" alt="${alt}" style="width: ${cssWidth}px; max-width: 100%;" />\n` +
      `</TerminalWindow>\n` +
      `</div>\n`
    )
  }
  return (
    `<div class="tachi-example-container">\n` +
    `<img src="${path}" alt="${alt}" style="width: ${cssWidth}px; max-width: 100%;" />\n` +
    `</div>\n`
  )
}

export function tachiExamplesPlugin(md: MarkdownIt, base: string = '/Tachikoma.jl/'): void {
  md.core.ruler.push('tachi_examples', (state) => {
    const src = state.tokens
    const out: typeof src = []
    let pendingAnnotation: TachiAnnotation | null = null

    let i = 0
    while (i < src.length) {
      const token = src[i]

      // --- Check for raw HTML comment annotation ---
      if (token.type === 'html_block') {
        const ann = parseAnnotation(token.content)
        if (ann) {
          pendingAnnotation = ann
          i++ // skip this token
          continue
        }
        // Strip tachi:noeval raw comments
        if (NOEVAL_RAW_RE.test(token.content)) {
          i++
          continue
        }
      }

      // --- Check for Documenter-escaped annotation (paragraph_open → inline → paragraph_close) ---
      if (token.type === 'paragraph_open' &&
          i + 2 < src.length &&
          src[i + 1].type === 'inline' &&
          src[i + 2].type === 'paragraph_close') {
        const ann = parseAnnotation(src[i + 1].content)
        if (ann) {
          pendingAnnotation = ann
          i += 3 // skip all three tokens
          continue
        }
        // Strip tachi:noeval escaped comments
        if (NOEVAL_ESCAPED_RE.test(src[i + 1].content)) {
          i += 3
          continue
        }
      }

      // --- Emit the current token ---
      out.push(token)

      // --- After a fence, inject image if we have a pending annotation ---
      if (token.type === 'fence' && pendingAnnotation) {
        const imgToken = new state.Token('html_block', '', 0)
        imgToken.content = makeImageHtml(pendingAnnotation, base)
        out.push(imgToken)
        pendingAnnotation = null
      }

      i++
    }

    // Replace token array in place
    state.tokens = out
  })
}
