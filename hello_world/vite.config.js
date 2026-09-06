import path from 'node:path';
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), '');
    const appName = env.VITE_APP_NAME;
    const uiBasePath = env.VITE_UI_BASE_PATH;
    if (!appName || !uiBasePath) {
        throw new Error('VITE_APP_NAME and VITE_UI_BASE_PATH must be set.');
    }
    return {
        plugins: [react(), tailwindcss()],
        // The @ alias is what the shadcn CLI writes into every component it adds.
        resolve: {
            alias: { '@': path.resolve(import.meta.dirname, './src') }
        },
        base: `/ords/${uiBasePath}/ui/${appName}/`
    };
});
