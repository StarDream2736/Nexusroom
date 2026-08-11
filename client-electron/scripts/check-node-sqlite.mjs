import { app } from 'electron';
import { DatabaseSync } from 'node:sqlite';

let exitCode = 0;
let database;
try {
  database = new DatabaseSync(':memory:');
  const row = database.prepare('SELECT 1 AS value').get();
  if (row?.value !== 1) {
    throw new Error('node:sqlite returned an unexpected result');
  }
  console.log(
    `Electron ${process.versions.electron ?? 'unknown'} loaded node:sqlite.`,
  );
} catch (error) {
  console.error('Electron node:sqlite check failed.', error);
  exitCode = 1;
} finally {
  database?.close();
}

app.exit(exitCode);
