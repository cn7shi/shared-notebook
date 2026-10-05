import { database, migrate } from '../src/infrastructure/database.js';
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
const pool = database(process.env.DATABASE_URL);
try { await migrate(pool); console.log('Migrations applied.'); } finally { await pool.end(); }
