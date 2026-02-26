import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import TerminalWindow from './TerminalWindow.vue'
import './style.css'
import './docstrings.css'

// Import GIFs as Vite assets so they're included in the build output
import heroLogoGif from '../../assets/hero_logo.gif'
import heroDemoGif from '../../assets/hero_demo.gif'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-hero-before': () =>
        h('div', { class: 'hero-logo-banner' }, [
          h('img', {
            src: heroLogoGif,
            alt: 'TACHIKOMA.jl',
            class: 'hero-logo-animated',
          }),
        ]),
      'home-hero-image': () =>
        h(TerminalWindow, { title: 'tachikoma — system monitor' }, () => [
          h('img', {
            src: heroDemoGif,
            alt: 'Tachikoma.jl system monitor demo',
          }),
        ]),
    })
  },
  enhanceApp({ app }) {
    // Register TerminalWindow globally so the tachi-examples plugin can use it
    app.component('TerminalWindow', TerminalWindow)
  },
} satisfies Theme
