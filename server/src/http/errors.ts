import { randomUUID } from 'node:crypto';
import { ArgumentsHost, Catch, type ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { Response } from 'express';
import { BusinessError } from '../domain/notebook.js';

@Catch()
export class ApiErrors implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    const requestId = randomUUID();
    let status = 500, code = 'INTERNAL_ERROR', message = '暂时无法完成操作，请稍后重试。';
    if (error instanceof BusinessError) ({ status, code, message } = error);
    else if (error instanceof HttpException) {
      status = error.getStatus();
      code = status === 400 ? 'VALIDATION_ERROR' : status === 404 ? 'NOT_FOUND' : status === 413 ? 'PAYLOAD_TOO_LARGE' : 'HTTP_ERROR';
      message = status === 400 ? '请求内容不符合接口要求。' : status === 413 ? '请求内容超过大小限制。' : '请求无法处理。';
    } else if (error && typeof error === 'object' && 'type' in error &&
      (error.type === 'entity.parse.failed' || error.type === 'entity.too.large')) {
      status = error.type === 'entity.too.large' ? 413 : 400;
      code = status === 413 ? 'PAYLOAD_TOO_LARGE' : 'VALIDATION_ERROR';
      message = status === 413 ? '请求内容超过大小限制。' : '请求内容不是有效的 JSON。';
    } else {
      // Never log request bodies, bearer tokens, password hashes, or database detail.
      Logger.error({ requestId, type: error instanceof Error ? error.name : 'UnknownError' }, 'ApiErrors');
    }
    response.setHeader('X-Request-Id', requestId);
    if (status === 429) response.setHeader('Retry-After', '60');
    response.status(status).json({ error: { code, message, requestId } });
  }
}
