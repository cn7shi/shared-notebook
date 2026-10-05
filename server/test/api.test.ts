import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:net';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import type { Pool } from 'pg';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { LocalPostgres } from '../scripts/local-postgres.js';
import { createApp } from '../src/app.js';
import { database, migrate } from '../src/infrastructure/database.js';
import { PostgresNotebook } from '../src/infrastructure/postgres-notebook.js';
import { DisabledProvider } from '../src/infrastructure/disabled-provider.js';
import { GenerationWorker } from '../src/application/generation.service.js';
import { NotebookService } from '../src/application/notebook.service.js';
import type { ModelContext, ModelProvider, NotebookTransaction } from '../src/domain/notebook.js';

class TestProvider implements ModelProvider {
  readonly id = 'test-only'; readonly available = true;
  contexts: ModelContext[] = [];
  handler: (c: ModelContext, s: AbortSignal) => Promise<{ body: string }> = async () => ({ body: '测试适配器生成的虚构内容' });
  generate(context: ModelContext, signal: AbortSignal) { this.contexts.push(structuredClone(context)); return this.handler(context, signal); }
}
const provider = new TestProvider();
function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve };
}
let cluster: LocalPostgres, pool: Pool, app: NestExpressApplication, worker: GenerationWorker;
let directory: string, base: string, databaseUrl: string, now = new Date();
let alice: { token: string; id: string }, bob: { token: string; id: string };
async function freePort() {
  const s = createServer(); await new Promise<void>(r => s.listen(0, '127.0.0.1', r));
  const port = (s.address() as { port: number }).port; await new Promise<void>((r, j) => s.close(e => e ? j(e) : r())); return port;
}
async function api(path: string, options: { method?: string; body?: unknown; token?: string; key?: string } = {}) {
  const response = await fetch(`${base}/api/v1${path}`, { method: options.method ?? 'GET', headers: {
    ...(options.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}), ...(options.key ? { 'Idempotency-Key': options.key } : {}),
  }, body: options.body !== undefined ? JSON.stringify(options.body) : undefined });
  const result = response.status === 204 ? null : await response.json() as any;
  return { status: response.status, data: result?.data, error: result?.error, headers: response.headers };
}
const read = (path: string, token?: string) => api(path, { token: token ?? alice.token });
const write = (path: string, body: unknown = {}, method = 'POST', key: string = randomUUID(), token?: string) => api(path, { method, body, key, token: token ?? alice.token });
async function register(email: string) {
  const r = await api('/auth/register', { method: 'POST', body: { email, password: 'a-long-test-password' } });
  assert.equal(r.status, 201); return { token: r.data.accessToken as string, id: r.data.user.id as string };
}
async function startApp() {
  ({ app, worker } = await createApp(pool, { provider, clock: () => now }));
  await app.listen(0, '127.0.0.1'); base = await app.getUrl();
}
before(async () => {
  directory = await mkdtemp(join(tmpdir(), 'shared-notebook-test-'));
  const password = randomBytes(18).toString('hex'), port = await freePort();
  cluster = new LocalPostgres({ databaseDir: join(directory, 'pg'), user: 'tester', password, port });
  await cluster.initialise(); await cluster.start(); databaseUrl = `postgresql://tester:${password}@127.0.0.1:${port}/postgres`;
  pool = database(databaseUrl); await migrate(pool); await startApp();
  alice = await register('alice@example.test'); bob = await register('bob@example.test');
}, { timeout: 120_000 });
beforeEach(async () => {
  // All data in this randomly allocated test cluster is synthetic and disposable.
  await pool.query('TRUNCATE receipts, messages, jobs, memories, conversations, grants, entries, characters CASCADE');
  provider.contexts = []; provider.handler = async () => ({ body: '测试适配器生成的虚构内容' }); now = new Date();
});
after(async () => {
  await app?.close(); await pool?.end(); await cluster?.stop();
  if (directory) {
    const target = resolve(directory); assert.equal(dirname(target), resolve(tmpdir()));
    assert.ok(basename(target).startsWith('shared-notebook-test-')); await rm(target, { recursive: true, force: true });
  }
});
async function character(name = '小舟', token?: string) {
  const r = await write('/characters', { name, background: '生活在虚构海边的角色', style: '平和，不替用户作决定' }, 'POST', randomUUID(), token);
  assert.equal(r.status, 201, JSON.stringify(r.error)); return r.data;
}
async function entry(body = '愿意分享的日常', token?: string) {
  const r = await write('/entries', { title: '今天', body }, 'POST', randomUUID(), token); assert.equal(r.status, 201); return r.data;
}
async function share(c: any, e: any, active = true, revision = 0) {
  const r = await write(`/characters/${c.id}/grants/${e.id}`, { active, revision, entryRevision: e.revision }, 'PUT');
  assert.equal(r.status, 200, JSON.stringify(r.error)); return r.data;
}
async function conversation(c: any, e?: any) {
  const r = await write(`/characters/${c.id}/conversations`, e ? { entryId: e.id } : {}); assert.equal(r.status, 201, JSON.stringify(r.error)); return r.data;
}
async function send(conv: any, body = '今天怎么样？') {
  const r = await write(`/conversations/${conv.id}/messages`, { body }); assert.equal(r.status, 202, JSON.stringify(r.error)); return r.data;
}
async function generated(c: any) {
  const r = await write(`/characters/${c.id}/diary-jobs`); assert.equal(r.status, 202, JSON.stringify(r.error));
  await worker.runOne(alice.id); const job = (await read(`/jobs/${r.data.id}`)).data; assert.equal(job.status, 'succeeded'); return job;
}

test('account authentication, strict inputs and private response headers', async () => {
  assert.equal((await api('/characters')).status, 401);
  assert.equal((await read('/auth/me')).data.id, alice.id);
  assert.equal((await write('/entries', { title: 'test', body: 'private', ownerId: bob.id })).status, 400);
  assert.equal((await write('/entries', { title: 'test', body: ' \n' })).status, 400);
  assert.equal((await write('/characters', { name: 'test', background: '', style: '' }, 'POST', 'bad')).status, 400);
  const r = await read('/characters'); assert.equal(r.headers.get('cache-control'), 'no-store');
  const login = await api('/auth/login', { method: 'POST', body: { email: 'alice@example.test', password: 'a-long-test-password' } });
  assert.equal(login.status, 200); assert.equal((await api('/auth/logout', { method: 'POST', token: login.data.accessToken })).status, 204);
  assert.equal((await read('/auth/me', login.data.accessToken)).status, 401);
  now = new Date(now.getTime() + 31 * 86400000); assert.equal((await read('/characters')).status, 401);
});

test('idempotency, canonical UUIDs and current-state replay never reapply revoked grants', async () => {
  const k = randomUUID(), input = { name: '同一角色', background: '', style: '' };
  const r = await Promise.all([write('/characters', input, 'POST', k), write('/characters', input, 'POST', k.toUpperCase())]);
  assert.deepEqual(r.map(v => v.status), [201, 201]); assert.equal(r[0]!.data.id, r[1]!.data.id);
  assert.equal((await write('/characters', { style: '', background: '', name: '同一角色' }, 'POST', k)).data.id, r[0]!.data.id);
  assert.equal((await write('/characters', { ...input, name: 'changed' }, 'POST', k)).error.code, 'IDEMPOTENCY_MISMATCH');
  const c = r[0]!.data, e = await entry(), grantKey = randomUUID(), b = { active: true, revision: 0, entryRevision: 1 };
  const granted = await write(`/characters/${c.id}/grants/${e.id}`, b, 'PUT', grantKey); assert.equal(granted.status, 200);
  await share(c, e, false, 1);
  const replay = await write(`/characters/${c.id.toUpperCase()}/grants/${e.id}`, b, 'PUT', grantKey);
  assert.equal(replay.data.active, false); assert.equal(replay.data.revision, 2);
  const receipt = await read(`/operations/${grantKey}`); assert.equal(receipt.data.resourceId, granted.data.id);
  assert.ok(!('fingerprint' in receipt.data)); assert.equal((await read(`/operations/${grantKey}`, bob.token)).status, 404);
});

test('concurrent edits and grants reject stale revisions without overwriting', async () => {
  const c = await character(), e = await entry();
  const writes = await Promise.all(['one', 'two'].map(body => write(`/entries/${e.id}`, { title: 'today', body, revision: 1 }, 'PUT')));
  assert.deepEqual(writes.map(r => r.status).sort(), [200, 409]);
  const current = (await read(`/entries/${e.id}`)).data;
  const grants = await Promise.all([true, false].map(active => write(`/characters/${c.id}/grants/${e.id}`, { active, entryRevision: current.revision, revision: 0 }, 'PUT')));
  assert.deepEqual(grants.map(r => r.status).sort(), [200, 409]);
});

test('private and other-character entries cannot enter model context or memory', async () => {
  const c = await character(), other = await character('另一个角色'), secret = await entry('NEVER_SEND_PRIVATE'), shared = await entry('ALLOWED_A'), onlyOther = await entry('ONLY_OTHER_CHARACTER');
  await share(c, shared); await share(other, onlyOther);
  assert.equal((await write(`/characters/${c.id}/conversations`, { entryId: secret.id })).error.code, 'ENTRY_NOT_SHARED');
  assert.equal((await write(`/characters/${c.id}/memories`, { body: 'hidden', active: true, sources: [{ entryId: secret.id, revision: 1 }] })).error.code, 'INVALID_SOURCE');
  const conv = await conversation(c, shared), job = await send(conv); await worker.runOne(alice.id);
  assert.equal((await read(`/jobs/${job.id}`)).data.status, 'succeeded');
  const context = JSON.stringify(provider.contexts[0]); assert.ok(context.includes('ALLOWED_A'));
  assert.ok(!context.includes('NEVER_SEND_PRIVATE') && !context.includes('ONLY_OTHER_CHARACTER'));
  assert.equal(provider.contexts[0]!.messages.at(-1)!.body, '今天怎么样？');
});

test('all resources and child collections enforce account and character boundaries', async () => {
  const c = await character(), other = await character(), foreign = await character('Bob', bob.token), e = await entry(), be = await entry('bob secret', bob.token);
  await share(c, e); const conv = await conversation(c, e), job = await send(conv); await worker.runOne(alice.id);
  const memory = (await write(`/characters/${c.id}/memories`, { body: '摘要', active: true, sources: [{ entryId: e.id, revision: 1 }] })).data;
  for (const route of [`/characters/${c.id}`, `/entries/${e.id}`, `/conversations/${conv.id}`, `/conversations/${conv.id}/messages`,
    `/characters/${c.id}/entries`, `/characters/${c.id}/grants`, `/characters/${c.id}/conversations`, `/characters/${c.id}/memories`, `/characters/${c.id}/jobs`, `/jobs/${job.id}`]) {
    assert.equal((await read(route, bob.token)).status, 404, route);
  }
  assert.equal((await write(`/characters/${c.id}/grants/${be.id}`, { active: true, revision: 0, entryRevision: 1 }, 'PUT')).status, 404);
  assert.equal((await write(`/characters/${foreign.id}/diary-jobs`)).status, 404);
  assert.equal((await write(`/characters/${other.id}/memories/${memory.id}`, { ...memory, revision: 1 }, 'PUT')).status, 400);
  assert.equal((await write(`/characters/${other.id}/memories/${memory.id}`, { body: 'tamper', active: true, sources: memory.sources, revision: 1 }, 'PUT')).status, 404);
  assert.equal((await write(`/conversations/${conv.id}/messages`, { body: 'tamper' }, 'POST', randomUUID(), bob.token)).status, 404);
});

test('editing a shared diary withdraws old consent and invalidates derived memory', async () => {
  const c = await character(), e = await entry('old shared text'); await share(c, e);
  const m = await write(`/characters/${c.id}/memories`, { body: 'old derived summary', active: true, sources: [{ entryId: e.id, revision: 1 }] }); assert.equal(m.status, 201);
  const queued = await write(`/characters/${c.id}/diary-jobs`);
  const updated = await write(`/entries/${e.id}`, { title: 'today', body: 'NEW_PRIVATE_TEXT', revision: 1 }, 'PUT'); assert.equal(updated.status, 200);
  assert.equal((await read(`/characters/${c.id}/grants`)).data.items[0].active, false);
  assert.equal((await read(`/characters/${c.id}/memories`)).data.items[0].active, false);
  assert.equal((await read(`/jobs/${queued.data.id}`)).data.status, 'cancelled');
  await generated(c); assert.ok(!JSON.stringify(provider.contexts[0]).includes('NEW_PRIVATE_TEXT'));
  await share(c, updated.data, true, 2); await generated(c);
  assert.ok(JSON.stringify(provider.contexts[1]).includes('NEW_PRIVATE_TEXT'));
});

test('withdrawal during generation cancels publication and drops old history on future requests', async () => {
  const c = await character(), e = await entry('WITHDRAWN_SOURCE'); await share(c, e);
  const conv = await conversation(c), first = await send(conv, 'Old user message quoting WITHDRAWN_SOURCE');
  provider.handler = async () => ({ body: 'OLD_DERIVED_REPLY' }); await worker.runOne(alice.id);
  assert.equal((await read(`/jobs/${first.id}`)).data.status, 'succeeded');
  const pending = await send(conv); const entered = deferred<void>(), result = deferred<{ body: string }>();
  provider.handler = async () => { entered.resolve(); return result.promise; };
  const run = worker.runOne(alice.id); await entered.promise; await share(c, e, false, 1);
  result.resolve({ body: 'STALE_RESULT_MUST_NOT_PUBLISH' }); await run;
  assert.equal((await read(`/jobs/${pending.id}`)).data.status, 'cancelled');
  const history = (await read(`/conversations/${conv.id}/messages`)).data.items;
  assert.ok(history.some((m: any) => m.body === 'OLD_DERIVED_REPLY'));
  assert.ok(!history.some((m: any) => m.body === 'STALE_RESULT_MUST_NOT_PUBLISH'));
  provider.handler = async () => ({ body: '新上下文' }); await send(conv, '重新聊聊'); await worker.runOne(alice.id);
  const next = JSON.stringify(provider.contexts.at(-1)); assert.ok(!next.includes('WITHDRAWN_SOURCE') && !next.includes('OLD_DERIVED_REPLY'));
});

test('late diary result is discarded when consent or character settings change', async () => {
  const c = await character(), e = await entry(); await share(c, e);
  const job = (await write(`/characters/${c.id}/diary-jobs`)).data;
  const entered = deferred<void>(), response = deferred<{ body: string }>();
  provider.handler = async () => { entered.resolve(); return response.promise; };
  const run = worker.runOne(alice.id); await entered.promise;
  assert.equal((await write(`/characters/${c.id}`, { name: '新名字', background: '新设定', style: '', revision: 1 }, 'PUT')).status, 200);
  response.resolve({ body: '旧设定的虚构经历' }); await run;
  assert.equal((await read(`/jobs/${job.id}`)).data.status, 'cancelled'); assert.deepEqual((await read(`/characters/${c.id}/entries`)).data.items, []);
});

test('disabled provider records a recoverable failure without emitting fabricated output', async () => {
  const c = await character(), conv = await conversation(c), job = await send(conv);
  const disabled = new GenerationWorker(new PostgresNotebook(pool), new DisabledProvider(), () => now); await disabled.runOne(alice.id);
  const failed = (await read(`/jobs/${job.id}`)).data;
  assert.equal(failed.status, 'failed'); assert.equal(failed.errorCode, 'PROVIDER_NOT_CONFIGURED'); assert.equal(failed.resultId, null);
  assert.equal((await read(`/conversations/${conv.id}/messages`)).data.items.length, 1); assert.equal(provider.contexts.length, 0);
  assert.ok(!('runToken' in failed) && !('leaseUntil' in failed));
  assert.equal((await write(`/jobs/${job.id}/retry`)).status, 202); await worker.runOne(alice.id);
  assert.equal((await read(`/jobs/${job.id}`)).data.status, 'succeeded');
});

test('duplicate message retries and workers publish once; newer turns invalidate old retries', async () => {
  const c = await character(), conv = await conversation(c), key = randomUUID(), body = { body: 'one message' };
  const sent = await Promise.all([write(`/conversations/${conv.id}/messages`, body, 'POST', key), write(`/conversations/${conv.id}/messages`, body, 'POST', key)]);
  assert.equal(sent[0]!.data.id, sent[1]!.data.id);
  assert.equal((await write(`/conversations/${conv.id}/messages`, { body: 'too early' })).error.code, 'GENERATION_BUSY');
  await Promise.all([worker.runOne(alice.id), worker.runOne(alice.id)]);
  assert.equal(provider.contexts.length, 1); assert.equal((await read(`/conversations/${conv.id}/messages`)).data.items.length, 2);
  const replay = await write(`/conversations/${conv.id}/messages`, body, 'POST', key); assert.equal(replay.data.status, 'succeeded');
  provider.handler = async () => { throw new Error('sensitive provider failure'); };
  const failed = await send(conv, 'old failed turn'); await worker.runOne(alice.id);
  await send(conv, 'new turn'); await worker.runOne(alice.id);
  assert.equal((await write(`/jobs/${failed.id}/retry`)).error.code, 'STALE_TURN');
});

test('timeout and expired worker leases are explicit failures; late workers are fenced', async () => {
  const c = await character(), conv = await conversation(c), job = await send(conv);
  provider.handler = async () => new Promise(() => {});
  await new GenerationWorker(new PostgresNotebook(pool), provider, () => now, 20).runOne(alice.id);
  assert.equal((await read(`/jobs/${job.id}`)).data.errorCode, 'PROVIDER_TIMEOUT');
  assert.equal((await write(`/jobs/${job.id}/retry`)).status, 202);
  const entered = deferred<void>(), result = deferred<{ body: string }>();
  provider.handler = async () => { entered.resolve(); return result.promise; };
  const run = worker.runOne(alice.id); await entered.promise; now = new Date(now.getTime() + 60_000);
  await new GenerationWorker(new PostgresNotebook(pool), provider, () => now).runOne(alice.id);
  assert.equal((await read(`/jobs/${job.id}`)).data.errorCode, 'WORKER_INTERRUPTED');
  result.resolve({ body: 'late content' }); await run;
  assert.equal((await read(`/conversations/${conv.id}/messages`)).data.items.length, 1);
});

test('fictional diary reads are stable and stale diaries cannot re-enter future context', async () => {
  const c = await character(), e = await entry('SOURCE_TO_REMOVE'); await share(c, e);
  provider.handler = async () => ({ body: 'OLD_FICTIONAL_DIARY' }); const job = await generated(c);
  assert.equal((await read(`/entries/${job.resultId}`)).data.author, 'character');
  assert.deepEqual((await read(`/characters/${c.id}/entries`)).data, (await read(`/characters/${c.id}/entries`)).data);
  assert.equal(provider.contexts.length, 1);
  assert.equal((await write(`/entries/${job.resultId}`, { title: 'overwrite', body: 'tamper', revision: 1 }, 'PUT')).error.code, 'IMMUTABLE_ENTRY');
  const another = await character('other'); assert.equal((await write(`/characters/${another.id}/conversations`, { entryId: job.resultId })).error.code, 'ENTRY_NOT_SHARED');
  await share(c, e, false, 1);
  assert.equal((await write(`/characters/${c.id}/conversations`, { entryId: job.resultId })).error.code, 'ENTRY_NOT_SHARED');
  await generated(c); assert.ok(!JSON.stringify(provider.contexts.at(-1)).includes('OLD_FICTIONAL_DIARY'));
});

test('memory revisions, invalidation and source checks affect only the authorized character', async () => {
  const c = await character(), other = await character(), e = await entry(); await share(c, e);
  const input = { body: '可以修正的摘要', active: true, sources: [{ entryId: e.id, revision: 1 }] };
  const m = await write(`/characters/${c.id}/memories`, input); assert.equal(m.status, 201);
  assert.equal((await write(`/characters/${other.id}/memories`, input)).error.code, 'INVALID_SOURCE');
  const update = await write(`/characters/${c.id}/memories/${m.data.id}`, { ...input, body: '修正后', revision: 1 }, 'PUT'); assert.equal(update.status, 200);
  assert.equal((await write(`/characters/${c.id}/memories/${m.data.id}`, { ...input, revision: 1 }, 'PUT')).error.code, 'REVISION_CONFLICT');
  await generated(c); assert.equal(provider.contexts[0]!.memories[0]!.body, '修正后');
  await write(`/characters/${c.id}/memories/${m.data.id}`, { ...input, active: false, revision: 2 }, 'PUT');
  await generated(c); assert.deepEqual(provider.contexts[1]!.memories, []);
});

test('an older selected diary is retained ahead of optional history within the context budget', async () => {
  const c = await character(); provider.handler = async () => ({ body: 'ANCHOR_DIARY_CONTENT' });
  const original = await generated(c);
  for (let i = 0; i < 6; i++) {
    now = new Date(now.getTime() + 1000); provider.handler = async () => ({ body: `Later diary ${i}` }); await generated(c);
  }
  const conv = await conversation(c, { id: original.resultId });
  provider.handler = async () => ({ body: 'x'.repeat(18000) });
  for (let i = 0; i < 7; i++) { await send(conv, '📝'.repeat(18000)); await worker.runOne(alice.id); }
  const context = provider.contexts.at(-1)!;
  assert.equal(context.characterEntries[0]!.id, original.resultId); assert.equal(context.characterEntries[0]!.body, 'ANCHOR_DIARY_CONTENT');
  assert.equal([...context.messages.at(-1)!.body].length, 18000);
  const texts = [context.character.name, context.character.background, context.character.style,
    ...context.messages.map(m => m.body), ...context.sharedEntries.flatMap(e => [e.title, e.body]),
    ...context.characterEntries.flatMap(e => [e.title, e.body]), ...context.memories.map(m => m.body)];
  assert.ok(texts.reduce((sum, value) => sum + [...value].length, 0) <= 48000);
});

test('provider failures and invalid output expose only stable errors and never publish', async () => {
  const c = await character();
  for (const result of ['', 'x'.repeat(20001)]) {
    provider.handler = async () => ({ body: result });
    const job = (await write(`/characters/${c.id}/diary-jobs`)).data; await worker.runOne(alice.id);
    assert.equal((await read(`/jobs/${job.id}`)).data.errorCode, 'INVALID_MODEL_RESULT');
  }
  provider.handler = async () => { throw new Error('secret-key-and-prompt-must-not-be-returned'); };
  const job = (await write(`/characters/${c.id}/diary-jobs`)).data; await worker.runOne(alice.id);
  const failed = await read(`/jobs/${job.id}`); assert.equal(failed.data.errorCode, 'PROVIDER_FAILURE');
  assert.ok(!JSON.stringify(failed).includes('secret-key')); assert.deepEqual((await read(`/characters/${c.id}/entries`)).data.items, []);
});

test('pagination remains ordered under equal timestamps and cursors cannot cross scopes', async () => {
  const c = await character(), conv = await conversation(c), other = await conversation(c);
  for (let i = 0; i < 3; i++) { await send(conv, `turn ${i}`); await worker.runOne(alice.id); }
  const first = (await read(`/conversations/${conv.id}/messages?limit=2`)).data;
  assert.deepEqual(first.items.map((m: any) => m.sequence), [6, 5]);
  const cursor = encodeURIComponent(first.nextCursor);
  assert.deepEqual((await read(`/conversations/${conv.id}/messages?limit=2&cursor=${cursor}`)).data.items.map((m: any) => m.sequence), [4, 3]);
  assert.equal((await read(`/conversations/${other.id}/messages?cursor=${cursor}`)).error.code, 'INVALID_CURSOR');
  assert.equal((await read('/entries?cursor=bad')).status, 400); assert.equal((await read('/entries?limit=101')).status, 400);
  const malformed = Buffer.from(JSON.stringify({ id: randomUUID(), createdAt: '2026-02-31T00:00:00.000Z',
    scope: JSON.stringify([alice.id, 'entries', { author: 'user' }]) })).toString('base64url');
  assert.equal((await read(`/entries?cursor=${malformed}`)).error.code, 'INVALID_CURSOR');
});

test('database enforces ownership, immutable output and transactional rollback', async () => {
  const c = await character(), foreign = await character('Bob', bob.token), e = await entry();
  await assert.rejects(pool.query('UPDATE entries SET character_id=$1,author=$2,context_version=1 WHERE id=$3', [foreign.id, 'character', e.id]), { code: '23503' });
  const job = await generated(c);
  await assert.rejects(pool.query('UPDATE entries SET body=$1 WHERE id=$2', ['tamper', job.resultId]), { code: '23514' });
  const repo = new PostgresNotebook(pool), n = new NotebookService({ pendingOwners: limit => repo.pendingOwners(limit),
    transact: (owner, write, action) => repo.transact(owner, write, tx => action(new Proxy(tx, {
      get(target, prop) {
        if (prop === 'save') return async (...args: Parameters<NotebookTransaction['save']>) => {
          if (args[0] === 'receipts') throw new Error('injected receipt failure'); return target.save(...args);
        };
        const value = Reflect.get(target, prop); return typeof value === 'function' ? value.bind(target) : value;
      },
    }))) });
  const before = Number((await pool.query('SELECT count(*) FROM entries')).rows[0].count);
  await assert.rejects(n.createEntry(alice.id, randomUUID(), { title: 'rollback', body: 'not committed' }), /injected/);
  assert.equal(Number((await pool.query('SELECT count(*) FROM entries')).rows[0].count), before);
});

test('app and PostgreSQL restart preserve jobs, grants, messages and sessions', async () => {
  const c = await character(), e = await entry(); await share(c, e); const conv = await conversation(c, e), job = await send(conv);
  await app.close(); await pool.end(); await cluster.stop(); await cluster.start(); pool = database(databaseUrl); await migrate(pool); await startApp();
  assert.equal((await read(`/jobs/${job.id}`)).data.status, 'pending'); assert.equal((await read(`/characters/${c.id}/grants`)).data.items[0].active, true);
  await worker.runOne(alice.id); assert.equal((await read(`/jobs/${job.id}`)).data.status, 'succeeded');
  assert.equal((await read(`/conversations/${conv.id}/messages`)).data.items.length, 2);
});

test('checked-in OpenAPI matches runtime with explicit errors, security and job fields', async () => {
  const { app: contractApp, document } = await createApp(pool);
  try {
    assert.deepEqual(document, JSON.parse(await readFile('../contracts/openapi.json', 'utf8')));
    assert.ok(document.paths['/api/v1/conversations/{id}/messages']!.post!.responses['202']);
    assert.ok(document.paths['/api/v1/characters/{id}/grants/{entryId}']!.put!.security?.length);
    const job = document.components!.schemas!.JobResponse as any;
    assert.ok(job.properties.status && job.properties.errorCode && job.properties.sources);
    assert.ok(!job.properties.runToken && !job.properties.leaseUntil);
  } finally { await contractApp.close(); }
});
