import { createApp } from './app.js';
import { database } from './infrastructure/database.js';
const url = process.env.DATABASE_URL;
if (!url) throw new Error('DATABASE_URL must be configured. Use npm run dev for isolated local development.');
const pool = database(url);
const { app } = await createApp(pool, { logging: true, startWorker: true,
  origins: process.env.CORS_ORIGINS?.split(',').map(origin => origin.trim()).filter(Boolean) });
await app.listen(Number(process.env.PORT ?? 3300), process.env.HOST ?? '127.0.0.1');
let stopping = false;
async function shutdown() { if (stopping) return; stopping = true; await app.close(); await pool.end(); }
process.once('SIGINT', () => { void shutdown(); });
process.once('SIGTERM', () => { void shutdown(); });
