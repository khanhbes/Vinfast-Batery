import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('@firebase/auth') || id.includes('/firebase/auth')) return 'firebase-auth'
          if (id.includes('@firebase/firestore') || id.includes('/firebase/firestore')) return 'firebase-firestore'
          if (id.includes('@firebase/') || id.includes('/firebase/')) return 'firebase-core'
          if (id.includes('/recharts/') || id.includes('/d3-')) return 'charts'
          if (id.includes('/motion/')) return 'motion'
          if (id.includes('/lucide-react/')) return 'icons'
          if (id.includes('/react/') || id.includes('/react-dom/') || id.includes('/react-router') || id.includes('/scheduler/')) return 'react'
          return undefined
        },
      },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true,
      },
    },
  },
})
