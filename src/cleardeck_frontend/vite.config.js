import { fileURLToPath, URL } from 'url';
import { execSync } from 'child_process';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { icpBindgen } from '@icp-sdk/bindgen/plugins/vite';

const environment = process.env.ICP_ENVIRONMENT || 'local';
const CANISTER_NAMES = ['lobby', 'table_1', 'history'];

function getCanisterId(name) {
  return execSync(`icp canister status ${name} -e ${environment} -i`, {
    encoding: 'utf-8',
    stdio: 'pipe',
  }).trim();
}

function getDevServerConfig() {
  const networkStatus = JSON.parse(
    execSync(`icp network status -e ${environment} --json`, {
      encoding: 'utf-8',
    })
  );
  const canisterParams = CANISTER_NAMES
    .map((name) => `PUBLIC_CANISTER_ID:${name}=${getCanisterId(name)}`)
    .join('&');
  return {
    headers: {
      'Set-Cookie': `ic_env=${encodeURIComponent(
        `${canisterParams}&IC_ROOT_KEY=${networkStatus.root_key}`
      )}; SameSite=Lax;`,
    },
    proxy: {
      '/api': { target: networkStatus.api_url, changeOrigin: true },
    },
  };
}

export default defineConfig(({ command }) => ({
  build: {
    emptyOutDir: true,
  },
  optimizeDeps: {
    esbuildOptions: {
      define: {
        global: 'globalThis',
      },
    },
  },
  ...(command === 'serve' ? { server: getDevServerConfig() } : {}),
  plugins: [
    sveltekit(),
    icpBindgen({
      didFile: '../lobby_canister/lobby_canister.did',
      outDir: './src/bindings',
    }),
    icpBindgen({
      didFile: '../table_canister/table_canister.did',
      outDir: './src/bindings',
    }),
    icpBindgen({
      didFile: '../history_canister/history_canister.did',
      outDir: './src/bindings',
    }),
  ],
}));
