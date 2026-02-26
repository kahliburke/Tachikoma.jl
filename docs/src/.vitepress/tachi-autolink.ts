/**
 * tachi-autolink.ts — VitePress markdown-it plugin for auto-linking API references
 *
 * Finds inline code spans (e.g. `Model`, `Frame`, `SelectableList`) that match
 * known Tachikoma API types/functions and wraps them in links to:
 *   - The API reference page anchor (for documented symbols)
 *   - The relevant guide page section (for concepts without docstrings)
 *
 * Skips headings and already-linked code to avoid noise.
 *
 * IMPORTANT: Links must NOT include the VitePress base path (/Tachikoma.jl/).
 * VitePress adds the base automatically during routing.
 */

import type MarkdownIt from 'markdown-it'
import type Token from 'markdown-it/lib/token.mjs'

// ── Symbol → link target mapping ──────────────────────────────────────
//
// Two kinds of entries:
//   1. API anchors: '/api#Tachikoma.Model' — links to exact docstring on API page
//   2. Guide pages: '/widgets#selectablelist' — links to guide section (for undocumented symbols)
//
// Prefer API anchors when the symbol has a docstring. The anchor format matches
// what Documenter generates: 'Tachikoma.Name' for types, 'Tachikoma.Name-Tuple{...}'
// for methods. We link to the type/simplest anchor for each name.

const API_LINKS: Record<string, string> = {
  // ── Core architecture ──
  'Model':          '/api#Tachikoma.Model',
  'Frame':          '/architecture#Frame-vs-Buffer',
  'Buffer':         '/architecture#Frame-vs-Buffer',
  'Terminal':       '/architecture#lifecycle',
  'AppOverlay':     '/architecture#AppOverlay-and-Default-Bindings',

  // ── Events ──
  'KeyEvent':       '/events#keyevent',
  'MouseEvent':     '/events#mouseevent',
  'MouseButton':    '/events#Mouse-Buttons',
  'MouseAction':    '/events#Mouse-Actions',
  'FocusRing':      '/api#Tachikoma.FocusRing',

  // ── Layout ──
  'Rect':           '/layout#rect',
  'Layout':         '/layout#Layout-and-split_layout',
  'Constraint':     '/layout#constraints',
  'Fixed':          '/api#Tachikoma.Fixed',
  'Fill':           '/api#Tachikoma.Fill',
  'Percent':        '/api#Tachikoma.Percent',
  'Min':            '/api#Tachikoma.Min',
  'Max':            '/api#Tachikoma.Max',
  'Ratio':          '/api#Tachikoma.Ratio',
  'Vertical':       '/layout#direction',
  'Horizontal':     '/layout#direction',
  'ResizableLayout': '/layout#resizablelayout',
  'Container':      '/layout#container',
  'split_layout':   '/api#Tachikoma.split_layout-Tuple{Layout, Rect}',

  // ── Styling ──
  'Style':          '/styling#style',
  'ColorRGB':       '/styling#colorrgb',
  'Color256':       '/styling#color256',
  'Theme':          '/styling#themes',
  'RenderBackend':  '/styling#Render-Backends',
  'DecayParams':    '/styling#Decay-Parameters',
  'TailwindPalette': '/styling#Theme-Struct',

  // ── Widgets — text display ──
  'Block':          '/widgets#block',
  'Paragraph':      '/api#Tachikoma.Paragraph-Tuple{AbstractString}',
  'Span':           '/widgets#paragraph',
  'BigText':        '/widgets#bigtext',
  'StatusBar':      '/widgets#statusbar',
  'Separator':      '/widgets#separator',

  // ── Widgets — input ──
  'TextInput':      '/api#Tachikoma.TextInput-Tuple{}',
  'TextArea':       '/api#Tachikoma.TextArea-Tuple{}',
  'CodeEditor':     '/api#Tachikoma.CodeEditor-Tuple{}',
  'Checkbox':       '/api#Tachikoma.Checkbox-Tuple{String}',
  'RadioGroup':     '/api#Tachikoma.RadioGroup-Tuple{Vector{String}}',
  'DropDown':       '/api#Tachikoma.DropDown-Tuple{Vector{String}}',
  'Calendar':       '/widgets#calendar',

  // ── Widgets — selection & navigation ──
  'SelectableList': '/api#Tachikoma.SelectableList-Tuple{Vector{ListItem}}',
  'ListItem':       '/widgets#selectablelist',
  'TreeView':       '/api#Tachikoma.TreeView-Tuple{TreeNode}',
  'TreeNode':       '/widgets#TreeView-/-TreeNode',
  'TabBar':         '/widgets#tabbar',
  'Modal':          '/widgets#modal',
  'ScrollPane':     '/widgets#scrollpane',
  'Scrollbar':      '/widgets#scrollbar',
  'Form':           '/api#Tachikoma.Form-Tuple{Vector{FormField}}',
  'FormField':      '/widgets#Form-/-FormField',
  'Button':         '/api#Tachikoma.Button-Tuple{String}',

  // ── Widgets — data visualization ──
  'Sparkline':      '/widgets#sparkline',
  'Gauge':          '/widgets#gauge',
  'BarChart':       '/widgets#barchart',
  'Chart':          '/widgets#chart',
  'DataSeries':     '/widgets#chart',
  'Table':          '/widgets#table',
  'DataTable':      '/widgets#datatable',
  'DataColumn':     '/api#Tachikoma.DataColumn-Tuple{String, Vector}',
  'ProgressList':   '/widgets#ProgressList-/-ProgressItem',
  'ProgressItem':   '/widgets#ProgressList-/-ProgressItem',
  'MarkdownPane':   '/api#Tachikoma.MarkdownPane-Tuple{AbstractString}',

  // ── Canvas & graphics ──
  'Canvas':         '/canvas#Canvas-Braille',
  'BlockCanvas':    '/canvas#BlockCanvas-Quadrant-Blocks',
  'PixelImage':     '/api#Tachikoma.PixelImage-Tuple{Int64, Int64}',
  'PixelCanvas':    '/canvas#PixelCanvas-Pixel-Drawing-Surface',

  // ── Animation ──
  'Tween':          '/animation#tweens',
  'Spring':         '/api#Tachikoma.Spring-Tuple{Real}',
  'Timeline':       '/animation#timelines',
  'Animator':       '/animation#animator',

  // ── Async ──
  'TaskQueue':      '/async#Setting-Up',
  'TaskEvent':      '/async#Handling-Results',
  'CancelToken':    '/async#Handling-Results',

  // ── Backgrounds ──
  'DotWaveBackground':   '/backgrounds#dotwavebackground',
  'PhyloTreeBackground': '/backgrounds#phylotreebackground',
  'CladogramBackground': '/backgrounds#cladogrambackground',
  'BackgroundConfig':    '/backgrounds#backgroundconfig',

  // ── Recording & Testing ──
  'CastRecorder':   '/recording#Programmatic-Recording',
  'TestBackend':    '/testing#testbackend',
}

export function tachiAutolinkPlugin(md: MarkdownIt): void {
  md.core.ruler.push('tachi_autolink', (state) => {
    const tokens = state.tokens
    let inHeading = false
    // Track which file we're processing to avoid self-links
    const env = state.env as { path?: string } | undefined
    const currentPage = env?.path?.replace(/\.md$/, '') || ''

    for (const token of tokens) {
      // Track heading context — don't auto-link inside headings
      if (token.type === 'heading_open') { inHeading = true; continue }
      if (token.type === 'heading_close') { inHeading = false; continue }
      if (inHeading) continue

      // Only process inline tokens (paragraph content, list items, etc.)
      if (token.type !== 'inline' || !token.children) continue

      const children = token.children
      const newChildren: Token[] = []
      let insideLink = false

      for (const child of children) {
        // Track link context — don't double-link
        if (child.type === 'link_open') { insideLink = true }
        if (child.type === 'link_close') { insideLink = false }

        if (child.type === 'code_inline' && !insideLink) {
          const name = child.content.trim()
          const target = API_LINKS[name]

          if (target) {
            // Don't create self-links (e.g. don't link `Model` on the architecture page
            // to the architecture page heading)
            const targetPage = target.split('#')[0]
            if (targetPage === '/' + currentPage) {
              newChildren.push(child)
              continue
            }

            // Create link_open → code_inline → link_close
            const linkOpen = new state.Token('link_open', 'a', 1)
            linkOpen.attrSet('href', target)
            linkOpen.attrSet('class', 'tachi-api-link')

            const linkClose = new state.Token('link_close', 'a', -1)

            newChildren.push(linkOpen, child, linkClose)
            continue
          }
        }

        newChildren.push(child)
      }

      token.children = newChildren
    }
  })
}
