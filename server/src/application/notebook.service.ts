import { createHash, randomUUID } from 'node:crypto';
import { BusinessError, type Clock, type Cursor, type Entities, type NotebookRepository, type NotebookTransaction,
  type ResourceKind, type Character, type Entry, type Source, type Job } from '../domain/notebook.js';

export const notFound = () => new BusinessError('NOT_FOUND', 404, '记录不存在。');
export async function required<K extends keyof Entities>(tx: NotebookTransaction, kind: K, id: string): Promise<Entities[K]> {
  const value = await tx.get(kind, id); if (!value) throw notFound(); return value;
}
function revision(actual: number, expected: number) {
  if (actual !== expected) throw new BusinessError('REVISION_CONFLICT', 409, '另一处已修改，请读取最新内容后选择。');
}
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, canonical(v)]));
  return value;
}
export async function all<K extends keyof Entities>(tx: NotebookTransaction, kind: K, filter: Partial<Entities[K]>) {
  const items: Entities[K][] = []; let before: Cursor | undefined;
  for (;;) {
    const page = await tx.list(kind, filter, 100, before); items.push(...page);
    if (page.length < 100) return items;
    const last = page.at(-1)!;
    before = { id: last.id, createdAt: last.createdAt, scope: '', ...('sequence' in last ? { sequence: last.sequence } : {}) };
  }
}
export async function sourceAllowed(tx: NotebookTransaction, characterId: string, source: Source) {
  const entry = await tx.get('entries', source.entryId);
  const grant = (await tx.list('grants', { characterId, entryId: source.entryId, active: true }, 1))[0];
  return !!entry && entry.author === 'user' && entry.revision === source.revision && grant?.entryRevision === source.revision;
}
export async function anchorAllowed(tx: NotebookTransaction, c: Character, entryId: string | null) {
  if (!entryId) return;
  const entry = await required(tx, 'entries', entryId);
  const allowed = entry.author === 'user'
    ? await sourceAllowed(tx, c.id, { entryId, revision: entry.revision })
    : entry.characterId === c.id && entry.contextVersion === c.contextVersion;
  if (!allowed) throw new BusinessError('ENTRY_NOT_SHARED', 409, '该记录尚未分享，或已不适用于当前上下文。');
}
export function publicJob(job: Job) {
  const { runToken: _token, leaseUntil: _lease, ...safe } = job; return safe;
}
export async function advanceContext(tx: NotebookTransaction, c: Character, now: string) {
  c.contextVersion++; c.updatedAt = now; await tx.save('characters', c);
  for (const job of await all(tx, 'jobs', { characterId: c.id })) {
    if (job.status !== 'pending' && job.status !== 'running') continue;
    job.status = 'cancelled'; job.errorCode = 'CONTEXT_CHANGED'; job.runToken = null; job.leaseUntil = null;
    job.updatedAt = now; await tx.save('jobs', job);
  }
}
export class NotebookService {
  constructor(readonly repository: NotebookRepository, private readonly clock: Clock = () => new Date()) {}
  private now() { return this.clock().toISOString(); }
  private write<K extends ResourceKind>(owner: string, key: string, operation: string, body: unknown, kind: K,
    action: (tx: NotebookTransaction) => Promise<Entities[K]>) {
    const fingerprint = createHash('sha256').update(JSON.stringify([operation, canonical(body)])).digest('hex');
    return this.repository.transact(owner, true, async tx => {
      const receipt = await tx.get('receipts', key);
      if (receipt) {
        if (receipt.fingerprint !== fingerprint || receipt.resourceKind !== kind) {
          throw new BusinessError('IDEMPOTENCY_MISMATCH', 409, '此请求标识已用于不同内容。');
        }
        // Replays return the resource's current state, never reapply an old grant.
        return required(tx, kind, receipt.resourceId);
      }
      const value = await action(tx);
      await tx.save('receipts', { id: key, operation, fingerprint, resourceKind: kind, resourceId: value.id, createdAt: this.now() });
      return value;
    });
  }
  read<K extends ResourceKind>(owner: string, kind: K, id: string) {
    return this.repository.transact(owner, false, tx => required(tx, kind, id));
  }
  list<K extends ResourceKind>(owner: string, kind: K, filter: Partial<Entities[K]>, limit: number, cursor?: string,
    parent?: { kind: ResourceKind; id: string }) {
    const scope = JSON.stringify([owner, kind, filter]); let before: Cursor | undefined;
    if (cursor) {
      try {
        before = JSON.parse(Buffer.from(cursor, 'base64url').toString());
        if (!before || before.scope !== scope || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(before.id) ||
          typeof before.createdAt !== 'string' || !Number.isFinite(Date.parse(before.createdAt)) ||
          new Date(before.createdAt).toISOString() !== before.createdAt ||
          (kind === 'messages' && (!Number.isSafeInteger(before.sequence) || before.sequence! < 1))) throw new Error();
      } catch { throw new BusinessError('INVALID_CURSOR', 400, '分页位置无效，请刷新列表。'); }
    }
    return this.repository.transact(owner, false, async tx => {
      if (parent) await required(tx, parent.kind, parent.id);
      const values = await tx.list(kind, filter, limit + 1, before), items = values.slice(0, limit), last = items.at(-1);
      const nextCursor = values.length > limit && last ? Buffer.from(JSON.stringify({ scope, id: last.id,
        createdAt: last.createdAt, ...('sequence' in last ? { sequence: last.sequence } : {}) })).toString('base64url') : null;
      return { items, nextCursor };
    });
  }
  operation(owner: string, key: string) {
    return this.repository.transact(owner, false, async tx => {
      const { fingerprint: _hash, ...receipt } = await required(tx, 'receipts', key); return receipt;
    });
  }
  createCharacter(owner: string, key: string, input: { name: string; background: string; style: string }) {
    return this.write(owner, key, 'create-character', input, 'characters', async tx => {
      const now = this.now(), c: Character = { id: randomUUID(), ...input, revision: 1, contextVersion: 1, createdAt: now, updatedAt: now };
      await tx.save('characters', c); return c;
    });
  }
  updateCharacter(owner: string, id: string, key: string, input: { name: string; background: string; style: string; revision: number }) {
    return this.write(owner, key, `update-character/${id}`, input, 'characters', async tx => {
      const c = await required(tx, 'characters', id); revision(c.revision, input.revision);
      Object.assign(c, input, { revision: c.revision + 1 }); await advanceContext(tx, c, this.now()); return c;
    });
  }
  createEntry(owner: string, key: string, input: { title: string; body: string }) {
    return this.write(owner, key, 'create-entry', input, 'entries', async tx => {
      const now = this.now(), entry: Entry = { id: randomUUID(), ...input, author: 'user', characterId: null,
        contextVersion: null, revision: 1, createdAt: now, updatedAt: now };
      await tx.save('entries', entry); return entry;
    });
  }
  updateEntry(owner: string, id: string, key: string, input: { title: string; body: string; revision: number }) {
    return this.write(owner, key, `update-entry/${id}`, input, 'entries', async tx => {
      const entry = await required(tx, 'entries', id);
      if (entry.author !== 'user') throw new BusinessError('IMMUTABLE_ENTRY', 409, '角色日记为已保存的虚构记录，不能覆盖。');
      revision(entry.revision, input.revision); const now = this.now();
      Object.assign(entry, input, { revision: entry.revision + 1, updatedAt: now }); await tx.save('entries', entry);
      for (const grant of await all(tx, 'grants', { entryId: id, active: true })) {
        grant.active = false; grant.revision++; grant.updatedAt = now; await tx.save('grants', grant);
        await this.invalidateMemories(tx, grant.characterId, id, now);
        await advanceContext(tx, await required(tx, 'characters', grant.characterId), now);
      }
      return entry;
    });
  }
  private async invalidateMemories(tx: NotebookTransaction, characterId: string, entryId: string, now: string) {
    for (const memory of await all(tx, 'memories', { characterId, active: true })) {
      if (!memory.sources.some(s => s.entryId === entryId)) continue;
      memory.active = false; memory.revision++; memory.updatedAt = now; await tx.save('memories', memory);
    }
  }
  share(owner: string, characterId: string, entryId: string, key: string, input: { active: boolean; entryRevision: number; revision: number }) {
    return this.write(owner, key, `share/${characterId}/${entryId}`, input, 'grants', async tx => {
      const c = await required(tx, 'characters', characterId), entry = await required(tx, 'entries', entryId);
      if (entry.author !== 'user') throw new BusinessError('INVALID_SOURCE', 400, '只能分享自己的日记。');
      if (input.active) revision(entry.revision, input.entryRevision);
      const previous = (await tx.list('grants', { characterId, entryId }, 1))[0]; revision(previous?.revision ?? 0, input.revision);
      const now = this.now(), grant = { id: previous?.id ?? randomUUID(), characterId, entryId,
        entryRevision: entry.revision, active: input.active, revision: (previous?.revision ?? 0) + 1,
        createdAt: previous?.createdAt ?? now, updatedAt: now };
      await tx.save('grants', grant);
      if (!grant.active) await this.invalidateMemories(tx, characterId, entryId, now);
      await advanceContext(tx, c, now); return grant;
    });
  }
  createConversation(owner: string, characterId: string, key: string, input: { entryId?: string }) {
    return this.write(owner, key, `create-conversation/${characterId}`, input, 'conversations', async tx => {
      const c = await required(tx, 'characters', characterId); await anchorAllowed(tx, c, input.entryId ?? null);
      const conversation = { id: randomUUID(), characterId, entryId: input.entryId ?? null, createdAt: this.now() };
      await tx.save('conversations', conversation); return conversation;
    });
  }
  private async availableSlot(tx: NotebookTransaction, characterId: string, conversationId: string | null) {
    const filter = conversationId ? { conversationId } : { characterId, kind: 'diary' as const };
    for (const status of ['pending', 'running'] as const) {
      if ((await tx.list('jobs', { ...filter, status }, 1)).length) throw new BusinessError('GENERATION_BUSY', 409, '上一项生成尚未结束。');
    }
  }
  private newJob(c: Character, kind: Job['kind'], conversationId: string | null, userMessageId: string | null): Job {
    const now = this.now(); return { id: randomUUID(), characterId: c.id, kind, conversationId, userMessageId,
      contextVersion: c.contextVersion, status: 'pending', attempt: 0, leaseUntil: null, runToken: null,
      resultId: null, errorCode: null, sources: [], createdAt: now, updatedAt: now };
  }
  send(owner: string, conversationId: string, key: string, input: { body: string }) {
    return this.write(owner, key, `send/${conversationId}`, input, 'jobs', async tx => {
      const conversation = await required(tx, 'conversations', conversationId);
      const c = await required(tx, 'characters', conversation.characterId); await anchorAllowed(tx, c, conversation.entryId);
      await this.availableSlot(tx, c.id, conversation.id);
      const messageId = randomUUID(), job = this.newJob(c, 'reply', conversation.id, messageId);
      const last = (await tx.list('messages', { conversationId }, 1))[0];
      await tx.save('jobs', job);
      await tx.save('messages', { id: messageId, characterId: c.id, conversationId, role: 'user', body: input.body,
        sequence: (last?.sequence ?? 0) + 1, contextVersion: c.contextVersion, jobId: null, createdAt: this.now() });
      return job;
    });
  }
  generateDiary(owner: string, characterId: string, key: string) {
    return this.write(owner, key, `generate-diary/${characterId}`, {}, 'jobs', async tx => {
      const c = await required(tx, 'characters', characterId); await this.availableSlot(tx, c.id, null);
      const job = this.newJob(c, 'diary', null, null); await tx.save('jobs', job); return job;
    });
  }
  retry(owner: string, id: string, key: string) {
    return this.write(owner, key, `retry-job/${id}`, {}, 'jobs', async tx => {
      const job = await required(tx, 'jobs', id), c = await required(tx, 'characters', job.characterId);
      if (job.status !== 'failed') throw new BusinessError('NOT_RETRYABLE', 409, '此任务不能重试，请发起新的请求。');
      if (job.contextVersion !== c.contextVersion) throw new BusinessError('CONTEXT_CHANGED', 409, '分享或背景已变化，请发起新的请求。');
      if (job.conversationId) {
        const latest = (await tx.list('messages', { conversationId: job.conversationId }, 1))[0];
        if (latest?.id !== job.userMessageId) throw new BusinessError('STALE_TURN', 409, '会话已继续，请发送新的消息。');
      }
      await this.availableSlot(tx, c.id, job.conversationId);
      job.status = 'pending'; job.errorCode = null; job.updatedAt = this.now(); await tx.save('jobs', job); return job;
    });
  }
  saveMemory(owner: string, characterId: string, id: string | null, key: string,
    input: { body: string; sources: Source[]; active: boolean; revision?: number }) {
    return this.write(owner, key, `save-memory/${characterId}/${id ?? 'new'}`, input, 'memories', async tx => {
      const c = await required(tx, 'characters', characterId), old = id ? await required(tx, 'memories', id) : null;
      if (old && old.characterId !== c.id) throw notFound();
      if (old) revision(old.revision, input.revision!);
      for (const source of input.sources) {
        const entry = await required(tx, 'entries', source.entryId);
        if (entry.author !== 'user' || (input.active && !await sourceAllowed(tx, characterId, source))) {
          throw new BusinessError('INVALID_SOURCE', 409, '记忆来源未获分享或已变化。');
        }
      }
      const now = this.now(), memory = { id: id ?? randomUUID(), characterId, body: input.body,
        sources: input.sources, active: input.active, revision: (old?.revision ?? 0) + 1, createdAt: old?.createdAt ?? now, updatedAt: now };
      await tx.save('memories', memory); await advanceContext(tx, c, now); return memory;
    });
  }
}
