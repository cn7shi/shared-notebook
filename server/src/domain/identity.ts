export interface User { id: string; email: string; passwordHash: string }
export interface Session { tokenHash: string; userId: string; expiresAt: string }
export interface IdentityRepository {
  findUser(email: string): Promise<User | null>;
  register(user: User, session: Session): Promise<void>;
  putSession(session: Session): Promise<void>;
  authenticate(tokenHash: string, now: Date): Promise<{ id: string; email: string } | null>;
  revoke(tokenHash: string): Promise<void>;
}
