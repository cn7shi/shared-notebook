import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { LocalPostgres } from './local-postgres.js';
import { createApp } from '../src/app.js';
import { database, migrate } from '../src/infrastructure/database.js';

const local = resolve('.local');
await mkdir(local, { recursive: true });
const settingsPath = resolve(local, 'postgres.json');
let settings: { password: string; port: number };
try { settings = JSON.parse(await readFile(settingsPath, 'utf8')); }
catch (error) {
  if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  settings = { password: randomBytes(24).toString('hex'), port: 54393 };
  await writeFile(settingsPath, JSON.stringify(settings), { mode: 0o600, flag: 'wx' });
}
const cluster = new LocalPostgres({ databaseDir: resolve(local, 'postgres'),
  user: 'shared-notebook', password: settings.password, port: settings.port });
await cluster.initialise();
await cluster.start();
const pool = database(`postgresql://shared-notebook:${settings.password}@127.0.0.1:${settings.port}/postgres`);
await migrate(pool);
const { app } = await createApp(pool, { logging: true, startWorker: true,
  origins: (process.env.CORS_ORIGINS ?? 'http://localhost:8080,http://127.0.0.1:8080').split(',') });
await app.listen(3300, '127.0.0.1');
console.log('Shared Notebook API: http://127.0.0.1:3300/api/docs (development, local-only)');
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  await app.close(); await pool.end(); await cluster.stop();
}
process.once('SIGINT', () => { void stop(); });
process.once('SIGTERM', () => { void stop(); });
