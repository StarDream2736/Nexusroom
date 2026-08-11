import { spawn, spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const electronCommand = join(
  projectRoot,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'electron.cmd' : 'electron',
);
const rendererUrl = 'http://127.0.0.1:5173';

const electronBuild = spawnSync(npmCommand, ['run', 'build:electron'], {
  cwd: projectRoot,
  stdio: 'inherit',
});

if (electronBuild.status !== 0) {
  process.exit(electronBuild.status ?? 1);
}

const renderer = spawn(
  npmCommand,
  ['run', 'dev:renderer', '--', '--host', '127.0.0.1', '--port', '5173'],
  {
    cwd: projectRoot,
    stdio: 'inherit',
  },
);
let electron;

const stopChildren = () => {
  if (!renderer.killed) {
    renderer.kill();
  }
  if (electron && !electron.killed) {
    electron.kill();
  }
};

const waitForRenderer = async () => {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(rendererUrl);
      if (response.ok) {
        return;
      }
    } catch {
      // Vite is still starting.
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  }
  throw new Error(`Renderer did not start at ${rendererUrl}`);
};

try {
  await waitForRenderer();
  electron = spawn(electronCommand, ['dist-electron/main.js'], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NEXUSROOM_RENDERER_URL: rendererUrl,
    },
    stdio: 'inherit',
  });
  electron.on('exit', (code, signal) => {
    stopChildren();
    process.exitCode = signal ? 1 : code ?? 0;
  });
} catch (error) {
  console.error(error);
  stopChildren();
  process.exitCode = 1;
}

process.on('SIGINT', stopChildren);
process.on('SIGTERM', stopChildren);
