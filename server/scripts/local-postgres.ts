import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash, randomBytes } from 'node:crypto';
import { access, cp, mkdir, readlink, symlink, unlink, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const run = promisify(execFile);

/** Development/test helper only; production connects to a separately managed DB.
 * Use pg_ctl for a graceful shutdown. PostgreSQL's Windows binaries need ASCII
 * installation paths, so only packaged binaries are cached outside the checkout.
 */
export class LocalPostgres {
  private native = '';
  private data = '';
  private running = false;
  constructor(private readonly options: { databaseDir: string; user: string; password: string; port: number }) {}

  async initialise() {
    const platform = process.platform === 'win32' ? 'windows' : process.platform;
    const pkg = `@embedded-postgres/${platform}-${process.arch}`;
    const binaries = await import(pkg) as { postgres: string; initdb: string; pg_ctl: string };
    this.native = dirname(dirname(binaries.postgres));
    this.data = resolve(this.options.databaseDir);
    if (process.platform === 'win32') {
      if (/[^\x00-\x7F]/.test(this.native)) {
        const cache = join(tmpdir(), 'shared-notebook-postgres-18.4.0-beta.17');
        try { await access(join(cache, '.complete')); }
        catch {
          await mkdir(cache, { recursive: true });
          await cp(this.native, cache, { recursive: true });
          await writeFile(join(cache, '.complete'), '18.4.0-beta.17');
        }
        this.native = cache;
      }
      if (/[^\x00-\x7F]/.test(this.data)) {
        // Keep persistent data in the project, using an ASCII junction as an alias.
        await mkdir(this.data, { recursive: true });
        const alias = join(tmpdir(), `shared-notebook-pg-data-${createHash('sha256').update(this.data).digest('hex').slice(0, 16)}`);
        try {
          const target = await readlink(alias);
          if (resolve(target).toLowerCase() !== this.data.toLowerCase()) throw new Error('Unexpected local database junction target');
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
          await symlink(this.data, alias, 'junction');
        }
        this.data = alias;
      }
    }
    try { await access(join(this.data, 'PG_VERSION')); return; } catch { /* Create only a new cluster. */ }
    const secret = join(tmpdir(), `shared-notebook-pg-password-${randomBytes(12).toString('hex')}`);
    await writeFile(secret, this.options.password + '\n', { mode: 0o600, flag: 'wx' });
    try {
      await run(this.executable('initdb'), ['-D', this.data, '--encoding=UTF8', '--locale=C',
        '--auth=scram-sha-256', `--username=${this.options.user}`, `--pwfile=${secret}`],
      { windowsHide: true, timeout: 60_000 });
    } finally { await unlink(secret); }
  }

  async start() {
    await run(this.executable('pg_ctl'), ['-D', this.data, '-l', join(this.data, 'server.log'),
      '-o', `-h 127.0.0.1 -p ${this.options.port}`, '-w', 'start'], { windowsHide: true, timeout: 60_000 });
    this.running = true;
  }

  async stop() {
    if (!this.running) return;
    await run(this.executable('pg_ctl'), ['-D', this.data, '-m', 'fast', '-w', 'stop'], { windowsHide: true, timeout: 60_000 });
    this.running = false;
  }

  private executable(name: string) { return join(this.native, 'bin', name + (process.platform === 'win32' ? '.exe' : '')); }
}
