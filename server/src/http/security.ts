import { CanActivate, type ExecutionContext, Inject, Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from '../application/auth.service.js';
import { BusinessError } from '../domain/notebook.js';

export interface AuthenticatedRequest extends Request { user: { id: string; email: string }; token: string }

@Injectable()
export class SessionGuard implements CanActivate {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    const token = header?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (!token) throw new BusinessError('UNAUTHORIZED', 401, '请先登录。');
    request.user = await this.auth.authenticate(token);
    request.token = token;
    return true;
  }
}

/** Bounded, process-local protection for the first single-instance release. */
@Injectable()
export class AuthRateGuard implements CanActivate {
  private readonly requests = new Map<string, { count: number; expires: number }>();
  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<Request>();
    const now = Date.now();
    for (const [key, value] of this.requests) if (value.expires <= now) this.requests.delete(key);
    // Express does not trust forwarded IPs unless the deployment explicitly enables it.
    const key = request.ip ?? request.socket.remoteAddress ?? 'unknown';
    const bucket = this.requests.get(key) ?? { count: 0, expires: now + 60_000 };
    if (bucket.count >= 20 || (!this.requests.has(key) && this.requests.size >= 10_000)) {
      throw new BusinessError('RATE_LIMITED', 429, '尝试过于频繁，请稍后再试。');
    }
    bucket.count++;
    this.requests.set(key, bucket);
    return true;
  }
}
