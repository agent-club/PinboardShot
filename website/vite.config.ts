import { cloudflare } from "@cloudflare/vite-plugin";
import vinext from "vinext";
import { defineConfig } from "vite";
import { sites } from "./build/sites-vite-plugin";

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === "seatbelt";

export default defineConfig(() => {
  // Package scripts set Wrangler's import-time log path before this config is
  // loaded. Keep the remaining non-secret tool state project-local.
  process.env.WRANGLER_WRITE_LOGS ??= "false";
  process.env.MINIFLARE_REGISTRY_PATH ??= ".wrangler/registry";

  return {
    server: isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : undefined,
    // vinext 1.1 emits relative imports to manifests in the server output root.
    // Keep RSC chunks beside them when Cloudflare splits the Worker entry point.
    environments: {
      rsc: {
        build: {
          rolldownOptions: { output: { chunkFileNames: "[name]-[hash].js" } },
        },
      },
    },
    plugins: [
      vinext(),
      sites(),
      cloudflare({
        viteEnvironment: { name: "rsc", childEnvironments: ["ssr"] },
        configPath: "./wrangler.jsonc",
      }),
    ],
  };
});
