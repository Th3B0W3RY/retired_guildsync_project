/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/assets/stylesheets/**/*.css',
    './app/javascript/**/*.js'
  ],
  darkMode: 'class', // Enable class-based dark mode
  theme: {
    extend: {
      colors: {
        // Dark theme color palette
        dark: {
          bg: {
            primary: '#0f172a',      // slate-900
            secondary: '#1e293b',     // slate-800
            tertiary: '#334155',      // slate-700
            card: '#1e293b',           // slate-800
            hover: '#334155',          // slate-700
          },
          text: {
            primary: '#f1f5f9',       // slate-100
            secondary: '#cbd5e1',     // slate-300
            tertiary: '#94a3b8',       // slate-400
            muted: '#64748b',          // slate-500
          },
          border: {
            primary: '#334155',       // slate-700
            secondary: '#475569',      // slate-600
          },
          accent: {
            primary: '#6366f1',        // indigo-500
            hover: '#818cf8',          // indigo-400
            light: '#a5b4fc',          // indigo-300
          },
        },
        // Light theme color palette (for future use)
        light: {
          bg: {
            primary: '#ffffff',
            secondary: '#f8fafc',
            tertiary: '#f1f5f9',
            card: '#ffffff',
            hover: '#f1f5f9',
          },
          text: {
            primary: '#0f172a',
            secondary: '#334155',
            tertiary: '#64748b',
            muted: '#94a3b8',
          },
          border: {
            primary: '#e2e8f0',
            secondary: '#cbd5e1',
          },
          accent: {
            primary: '#6366f1',
            hover: '#818cf8',
            light: '#a5b4fc',
          },
        },
      },
    },
  },
  plugins: [],
}

