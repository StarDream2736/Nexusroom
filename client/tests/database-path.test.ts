import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  CLIENT_DATABASE_FILE,
  CLIENT_DATA_DIRECTORY,
  resolveClientDatabasePath,
} from '../src/main/database-path';

describe('resolveClientDatabasePath', () => {
  it('uses client/data in development', () => {
    const developmentRoot = resolve('client');

    expect(
      resolveClientDatabasePath({
        isPackaged: false,
        executablePath: resolve('NexusRoom.exe'),
        developmentRoot,
      }),
    ).toBe(join(developmentRoot, CLIENT_DATA_DIRECTORY, CLIENT_DATABASE_FILE));
  });

  it('uses data beside the packaged executable', () => {
    const executablePath = resolve('portable', 'NexusRoom.exe');
    const executableDirectory = resolve('portable');

    expect(
      resolveClientDatabasePath({
        isPackaged: true,
        executablePath,
        developmentRoot: resolve('client'),
      }),
    ).toBe(join(executableDirectory, CLIENT_DATA_DIRECTORY, CLIENT_DATABASE_FILE));
  });
});
