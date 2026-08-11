import { dirname, join, resolve } from 'node:path';

export const CLIENT_DATA_DIRECTORY = 'data';
export const CLIENT_DATABASE_FILE = 'nexusroom.sqlite';

export interface ClientDatabasePathOptions {
  readonly isPackaged: boolean;
  readonly executablePath: string;
  readonly developmentRoot: string;
}

export function resolveClientDatabasePath(
  options: ClientDatabasePathOptions,
): string {
  const root = options.isPackaged
    ? dirname(resolve(options.executablePath))
    : resolve(options.developmentRoot);
  return join(root, CLIENT_DATA_DIRECTORY, CLIENT_DATABASE_FILE);
}
