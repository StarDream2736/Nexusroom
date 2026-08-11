import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

interface PackageConfig {
  readonly build?: {
    readonly files?: readonly string[];
  };
}

const packageConfig = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
) as PackageConfig;

describe('Electron packaging configuration', () => {
  it('keeps compiled main JavaScript while excluding source maps', () => {
    const files = packageConfig.build?.files ?? [];

    expect(files).toContain('dist-electron/**/*');
    expect(files).toContain('!**/*.map');
  });
});
