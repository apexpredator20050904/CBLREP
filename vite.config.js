import { defineConfig, loadEnv } from 'vite'
import react, { reactCompilerPreset } from '@vitejs/plugin-react'
import babel from '@rolldown/plugin-babel'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Read VITE_* values from frontend/.env (e.g. VITE_API_TARGET, VITE_API_BASE_URL).
  const env = loadEnv(mode, process.cwd(), '')

  // Where the Vite dev-server proxy forwards /api/* requests. Defaults to a
  // local backend; set VITE_API_TARGET in frontend/.env (e.g. to your LAN IP,
  // http://<PC-IP>:8000) to reach a backend on another host or a phone.
  const apiTarget = env.VITE_API_TARGET || 'http://localhost:8000'

  return {
    plugins: [
      react(),
      babel({ presets: [reactCompilerPreset()] }),
      tailwindcss(),
    ],
    server: {
      // Bind to 0.0.0.0 (Vite's default is localhost-only) so a physical
      // device can load the dev server over the local network.
      host: true,
      port: 5173,
      // Forward all /api/* calls to the Laravel backend (php artisan serve).
      proxy: {
        '/api': {
          target: apiTarget,
          changeOrigin: true,
        },
      },
    },
  }
})
