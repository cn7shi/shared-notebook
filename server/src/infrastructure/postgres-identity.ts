import type { Pool } from 'pg';
import type { IdentityRepository, Session, User } from '../domain/identity.js';
import { BusinessError } from '../domain/notebook.js';
import { transaction } from './database.js';

export class PostgresIdentity implements IdentityRepository {
  constructor(private readonly pool: Pool) {}

  async findUser(email: string) {
    const result = await this.pool.query('SELECT id,email,password_hash FROM users WHERE email=$1', [email]);
    const row = result.rows[0];
    return row ? { id: row.id, email: row.email, passwordHash: row.password_hash } : null;
  }

  async register(user: User, session: Session) {
    try {
      await transaction(this.pool, async client => {
        await client.query('INSERT INTO users(id,email,password_hash) VALUES($1,$2,$3)', [user.id, user.email, user.passwordHash]);
        await client.query('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)', [session.tokenHash, session.userId, session.expiresAt]);
      });
    } catch (error) {
      if ((error as { code?: string }).code === '23505') throw new BusinessError('ACCOUNT_EXISTS', 409, '这个邮箱已注册，请登录。');
      throw error;
    }
  }

  async putSession(session: Session) {
    await this.pool.query('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)', [session.tokenHash, session.userId, session.expiresAt]);
  }

  async authenticate(tokenHash: string, now: Date) {
    const result = await this.pool.query('SELECT u.id,u.email FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>$2', [tokenHash, now]);
    return result.rows[0] ? { id: result.rows[0].id as string, email: result.rows[0].email as string } : null;
  }

  async revoke(tokenHash: string) { await this.pool.query('DELETE FROM sessions WHERE token_hash=$1', [tokenHash]); }
}
