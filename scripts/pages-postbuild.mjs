import { writeFileSync, cpSync, rmSync } from 'node:fs';
import { build } from 'esbuild';

// 1. Move static assets to dist/ root for Pages ASSETS binding
cpSync('dist/client', 'dist', { recursive: true, force: true });
rmSync('dist/client', { recursive: true, force: true });

// 2. Bundle worker into single _worker.js for Pages Advanced Mode
await build({
  entryPoints: ['dist/server/entry.mjs'],
  bundle: true,
  format: 'esm',
  platform: 'neutral',
  outfile: 'dist/_worker.js',
  external: ['cloudflare:*', 'node:*'],
  minify: true,
});

// 3. _routes.json for Pages routing
writeFileSync('dist/_routes.json', JSON.stringify({
  version: 1,
  include: ['/*'],
  exclude: ['/_astro/*'],
}, null, 2) + '\n');

console.log('✅ dist/ ready for Cloudflare Pages (Advanced Mode)');
