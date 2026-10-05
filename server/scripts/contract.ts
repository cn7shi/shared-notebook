import { mkdir, writeFile } from 'node:fs/promises';
import { createApp } from '../src/app.js';
import { database } from '../src/infrastructure/database.js';

// Generating the HTTP contract must not require a running database.
const pool = database('postgresql://unused:unused@127.0.0.1:1/unused');
const { app, document } = await createApp(pool);
await mkdir('../contracts', { recursive: true });
await writeFile('../contracts/openapi.json', JSON.stringify(document, null, 2) + '\n');
await app.close();
await pool.end();
console.log('Wrote contracts/openapi.json');
