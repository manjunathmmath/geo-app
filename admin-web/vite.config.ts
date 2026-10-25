import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In development the API and the uploaded media are proxied so the browser sees one origin
// (no CORS). In production, Caddy does the same routing on the VM.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8080',
      '/media': 'http://localhost:8080',
    },
  },
});
