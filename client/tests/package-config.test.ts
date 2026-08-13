import { build } from 'vite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

interface PackageConfig {
  readonly build?: {
    readonly files?: readonly string[];
  };
}

const packageConfig = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
) as PackageConfig;

interface ViteOutputAsset {
  readonly type: 'asset';
  readonly fileName: string;
  readonly source: string | Uint8Array;
}

interface ViteOutputChunk {
  readonly type: 'chunk';
  readonly fileName: string;
}

type ViteOutput = ViteOutputAsset | ViteOutputChunk;

interface RollupBuildResult {
  readonly output: readonly ViteOutput[];
}

function hasOutput(value: unknown): value is RollupBuildResult {
  return (
    typeof value === 'object' &&
    value !== null &&
    'output' in value &&
    Array.isArray(value.output)
  );
}

function outputIndexHtml(output: readonly ViteOutput[]): string {
  const indexAsset = output.find(
    (entry): entry is ViteOutputAsset =>
      entry.type === 'asset' && entry.fileName === 'index.html',
  );
  expect(indexAsset).toBeDefined();
  if (indexAsset === undefined) {
    throw new Error('Vite did not emit dist/renderer/index.html.');
  }
  return typeof indexAsset.source === 'string'
    ? indexAsset.source
    : new TextDecoder().decode(indexAsset.source);
}

describe('Electron packaging configuration', () => {
  it('keeps compiled main JavaScript while excluding source maps', () => {
    const files = packageConfig.build?.files ?? [];

    expect(files).toContain('dist-electron/**/*');
    expect(files).toContain('!**/*.map');
  });

  it('builds renderer entry assets with file://-safe relative URLs', async () => {
    const clientRoot = fileURLToPath(new URL('..', import.meta.url));
    const result = await build({
      root: clientRoot,
      configFile: resolve(clientRoot, 'vite.config.mjs'),
      build: {
        write: false,
      },
    });
    const output = Array.isArray(result)
      ? result.find(hasOutput)?.output
      : hasOutput(result)
        ? result.output
        : undefined;
    const indexHtml = outputIndexHtml(output ?? []);
    const rendererAssets = [...indexHtml.matchAll(/(?:src|href)="([^"]+)"/g)]
      .map((match) => match[1])
      .filter((reference): reference is string =>
        reference !== undefined && /\.(?:js|css)$/.test(reference),
      );

    expect(rendererAssets.length).toBeGreaterThanOrEqual(2);
    expect(rendererAssets.every((reference) => reference.startsWith('./assets/')))
      .toBe(true);
  });
});
