import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import { tachiExamplesPlugin } from './tachi-examples'
import { tachiAutolinkPlugin } from './tachi-autolink'

export default defineConfig({
  base: '/Tachikoma.jl/',
  title: 'Tachikoma.jl',
  description: 'Terminal UI framework for Julia',
  lastUpdated: true,
  cleanUrls: true,

  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin)
      md.use(tachiExamplesPlugin)
      md.use(tachiAutolinkPlugin)
    },
  },

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/getting-started' },
      { text: 'Widgets', link: '/widgets' },
      { text: 'API', link: '/api' },
    ],

    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Installation', link: '/installation' },
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Architecture', link: '/architecture' },
        ],
      },
      {
        text: 'Core Concepts',
        items: [
          { text: 'Layout', link: '/layout' },
          { text: 'Styling & Themes', link: '/styling' },
          { text: 'Input & Events', link: '/events' },
          { text: 'Pattern Matching', link: '/match' },
          { text: 'Async Tasks', link: '/async' },
          { text: 'Preferences', link: '/preferences' },
        ],
      },
      {
        text: 'Widgets & Graphics',
        items: [
          { text: 'Widgets', link: '/widgets' },
          { text: 'Graphics & Pixel Rendering', link: '/canvas' },
          { text: 'Animation', link: '/animation' },
          { text: 'Backgrounds', link: '/backgrounds' },
        ],
      },
      {
        text: 'Advanced',
        items: [
          { text: 'Performance', link: '/performance' },
          { text: 'Recording & Export', link: '/recording' },
          { text: 'Scripting Interactions', link: '/scripting' },
          { text: 'Testing', link: '/testing' },
        ],
      },
      {
        text: 'Tutorials',
        items: [
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Game of Life', link: '/tutorials/game-of-life' },
          { text: 'Build a Form', link: '/tutorials/form-app' },
          { text: 'Build a Dashboard', link: '/tutorials/dashboard' },
          { text: 'Animation Showcase', link: '/tutorials/animation-showcase' },
          { text: 'Todo List', link: '/tutorials/todo-list' },
          { text: 'GitHub PR Viewer', link: '/tutorials/github-prs' },
          { text: 'Constraint Explorer', link: '/tutorials/constraint-explorer' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'API Reference', link: '/api' },
          { text: 'Comparison', link: '/comparison' },
        ],
      },
    ],

    outline: {
      level: [2, 3],
    },

    search: {
      provider: 'local',
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/kahliburke/Tachikoma.jl' },
    ],
    footer: {
      message: 'Made with <a href="https://documenter.juliadocs.org/stable/">Documenter.jl</a> and <a href="https://vitepress.dev">VitePress</a>',
      copyright: 'Copyright © 2025-present',
    },
  },
})
