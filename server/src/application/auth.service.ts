import { createHash, randomBytes, randomUUID, scrypt, timingSafeEqual } from 'node:crypto';
import type { IdentityRepository, User } from '../domain/identity.js';
import { BusinessError, type Clock } from '../domain/notebook.js';

function derive(password: string, salt: string): Promise<Buffer> {
  return new Promise((resolve, reject) => scrypt(password, salt, 64,
    { N: 16384, r: 8, p: 1 }, (error, key) => error ? reject(error) : resolve(key)));
}
export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');

export class AuthService {
  constructor(private readonly repository: IdentityRepository, private readonly clock: Clock = () => new Date()) {}

  async register(email: string, password: string) {
    const salt = randomBytes(16).toString('hex');
    const hash = (await derive(password, salt)).toString('hex');
    const user = { id: randomUUID(), email: email.trim().toLowerCase(), passwordHash: `scrypt-v1$${salt}$${hash}` };
    const issued = this.issue(user);
    await this.repository.register(user, issued.session);
    return issued.response;
  }

  async login(email: string, password: string) {
    const user = await this.repository.findUser(email.trim().toLowerCase());
    const [, salt, hash] = user?.passwordHash.split('$') ?? ['scrypt-v1', '0'.repeat(32), '0'.repeat(128)];
    const candidate = await derive(password, salt!);
    const stored = Buffer.from(hash!, 'hex');
    if (!user || stored.length !== candidate.length || !timingSafeEqual(candidate, stored)) {
      throw new BusinessError('INVALID_CREDENTIALS', 401, '邮箱或密码不正确。');
    }
    const issued = this.issue(user);
    await this.repository.putSession(issued.session);
    return issued.response;
  }

  async authenticate(token: string) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new BusinessError('UNAUTHORIZED', 401, '请先登录。');
    const user = await this.repository.authenticate(hashToken(token), this.clock());
    if (!user) throw new BusinessError('UNAUTHORIZED', 401, '登录已过期，请重新登录。');
    return user;
  }

  revoke(token: string) { return this.repository.revoke(hashToken(token)); }

  private issue(user: User) {
    const accessToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(this.clock().getTime() + 30 * 24 * 60 * 60_000).toISOString();
    return { session: { tokenHash: hashToken(accessToken), userId: user.id, expiresAt },
      response: { accessToken, expiresAt, user: { id: user.id, email: user.email } } };
  }
}
