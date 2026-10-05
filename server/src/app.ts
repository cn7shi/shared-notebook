import 'reflect-metadata';
import { Module, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import type { Pool } from 'pg';
import helmet from 'helmet';
import { json, type Request, type Response } from 'express';
import { AuthService } from './application/auth.service.js';
import { NotebookService } from './application/notebook.service.js';
import { GenerationWorker } from './application/generation.service.js';
import type { Clock, ModelProvider } from './domain/notebook.js';
import { PostgresIdentity } from './infrastructure/postgres-identity.js';
import { PostgresNotebook } from './infrastructure/postgres-notebook.js';
import { DisabledProvider } from './infrastructure/disabled-provider.js';
import { AuthController, NotebookController } from './http/controllers.js';
import { ApiErrors } from './http/errors.js';
import { AuthRateGuard, SessionGuard } from './http/security.js';

export async function createApp(pool: Pool, options: { clock?: Clock; logging?: boolean; origins?: string[];
  provider?: ModelProvider; startWorker?: boolean; generationTimeoutMs?: number } = {}) {
  const repository = new PostgresNotebook(pool);
  const worker = new GenerationWorker(repository, options.provider ?? new DisabledProvider(), options.clock, options.generationTimeoutMs);
  @Module({ controllers: [AuthController, NotebookController], providers: [SessionGuard, AuthRateGuard,
    { provide: AuthService, useValue: new AuthService(new PostgresIdentity(pool), options.clock) },
    { provide: NotebookService, useValue: new NotebookService(repository, options.clock) },
    { provide: GenerationWorker, useValue: worker },
  ] }) class AppModule {}
  const app = await NestFactory.create<NestExpressApplication>(AppModule,
    { logger: options.logging ? ['error', 'warn', 'log'] : false, bodyParser: false, abortOnError: false });
  app.use(helmet()); app.use(json({ limit: '512kb' }));
  app.use((_req: unknown, res: { setHeader(name: string, value: string): void }, next: () => void) => { res.setHeader('Cache-Control', 'no-store'); next(); });
  if (options.origins?.length) app.enableCors({ origin: options.origins,
    allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'], methods: ['GET', 'POST', 'PUT'] });
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true, forbidNonWhitelisted: true, validationError: { target: false, value: false } }));
  app.useGlobalFilters(new ApiErrors());
  const document = SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('Shared Notebook API').setVersion('1.0.0')
    .setDescription('Private diaries, explicit per-character sharing, fictional character diaries, durable generation jobs. Provider disabled until configured.')
    .addBearerAuth({ type: 'http', scheme: 'bearer', description: 'Opaque session token from /auth/login or /auth/register.' }).build());
  SwaggerModule.setup('api/docs', app, document);
  app.getHttpAdapter().getInstance().get('/health', async (_req: Request, res: Response) => {
    try { await pool.query('SELECT 1'); res.json({ status: 'ok' }); } catch { res.status(503).json({ status: 'unavailable' }); }
  });
  await app.init(); if (options.startWorker) worker.start(); return { app, document, worker };
}
