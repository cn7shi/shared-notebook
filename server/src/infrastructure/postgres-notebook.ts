import type { Pool, PoolClient } from 'pg';
import { BusinessError, type Cursor, type Entities, type NotebookRepository, type NotebookTransaction } from '../domain/notebook.js';
import { transaction } from './database.js';

// Fixed mappings keep SQL identifiers independent of caller-provided fields.
const fields = {
  characters: ['id', 'name', 'background', 'style', 'revision', 'contextVersion', 'createdAt', 'updatedAt'],
  entries: ['id', 'author', 'characterId', 'title', 'body', 'revision', 'contextVersion', 'createdAt', 'updatedAt'],
  grants: ['id', 'characterId', 'entryId', 'entryRevision', 'active', 'revision', 'createdAt', 'updatedAt'],
  conversations: ['id', 'characterId', 'entryId', 'createdAt'],
  messages: ['id', 'characterId', 'conversationId', 'role', 'body', 'sequence', 'contextVersion', 'jobId', 'createdAt'],
  memories: ['id', 'characterId', 'body', 'sources', 'active', 'revision', 'createdAt', 'updatedAt'],
  jobs: ['id', 'characterId', 'conversationId', 'userMessageId', 'kind', 'status', 'contextVersion', 'attempt',
    'leaseUntil', 'runToken', 'resultId', 'errorCode', 'sources', 'createdAt', 'updatedAt'],
  receipts: ['id', 'operation', 'fingerprint', 'resourceKind', 'resourceId', 'createdAt'],
} as const;
const column = (name: string) => name.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`);

export class PostgresNotebook implements NotebookRepository {
  constructor(private readonly pool: Pool) {}
  transact<T>(owner: string, write: boolean, action: (tx: NotebookTransaction) => Promise<T>) {
    return transaction(this.pool, async client => {
      const user = await client.query(`SELECT id FROM users WHERE id=$1 FOR ${write ? 'UPDATE' : 'SHARE'}`, [owner]);
      if (!user.rowCount) throw new BusinessError('NOT_FOUND', 404, '账户不存在。');
      return action(new PostgresTransaction(client, owner));
    });
  }
  async pendingOwners(limit: number) {
    const rows = await this.pool.query(`SELECT owner_id, min(created_at) AS first_job FROM jobs
      WHERE status IN ('pending','running') GROUP BY owner_id ORDER BY first_job LIMIT $1`, [limit]);
    return rows.rows.map(row => row.owner_id as string);
  }
}

class PostgresTransaction implements NotebookTransaction {
  constructor(private readonly client: PoolClient, private readonly owner: string) {}
  async get<K extends keyof Entities>(kind: K, id: string) {
    return (await this.list(kind, { id } as Partial<Entities[K]>, 1))[0] ?? null;
  }
  async list<K extends keyof Entities>(kind: K, filter: Partial<Entities[K]>, limit: number, before?: Cursor) {
    const values: unknown[] = [this.owner];
    const where = ['owner_id=$1'];
    for (const [key, value] of Object.entries(filter)) {
      if (!(fields[kind] as readonly string[]).includes(key)) throw new Error('Unknown repository filter');
      if (value === null) where.push(`${column(key)} IS NULL`);
      else { values.push(value); where.push(`${column(key)}=$${values.length}`); }
    }
    if (before) {
      if (kind === 'messages') { values.push(before.sequence); where.push(`sequence<$${values.length}`); }
      else {
        values.push(before.createdAt, before.id);
        where.push(`(created_at,id)<($${values.length - 1}::timestamptz,$${values.length}::uuid)`);
      }
    }
    values.push(limit);
    const result = await this.client.query(`SELECT * FROM ${kind} WHERE ${where.join(' AND ')}
      ORDER BY ${kind === 'messages' ? 'sequence DESC' : 'created_at DESC,id DESC'} LIMIT $${values.length}`, values);
    return result.rows.map(row => Object.fromEntries(fields[kind].map(field => {
      const value = row[column(field)];
      return [field, value instanceof Date ? value.toISOString() : value];
    })) as unknown as Entities[K]);
  }
  async save<K extends keyof Entities>(kind: K, value: Entities[K]) {
    const names = fields[kind] as readonly string[];
    const values = names.map(field => {
      const item = (value as unknown as Record<string, unknown>)[field];
      return field === 'sources' ? JSON.stringify(item) : item;
    });
    await this.client.query(`INSERT INTO ${kind}(owner_id,${names.map(column).join(',')})
      VALUES($1,${names.map((_, i) => `$${i + 2}`).join(',')})
      ON CONFLICT(owner_id,id) DO UPDATE SET ${names.filter(f => f !== 'id').map(f => `${column(f)}=EXCLUDED.${column(f)}`).join(',')}`,
    [this.owner, ...values]);
  }
}
