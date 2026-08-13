import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
  },
  esbuild: {
    jsx: 'automatic',
  },
  build: {
    emptyOutDir: true,
    outDir: 'dist/renderer',
  },
});
