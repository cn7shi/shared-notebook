import { applyDecorators, Body, Controller, Get, Headers, HttpCode, Inject, Param, ParseUUIDPipe, Post, Put, Query, Req, UseGuards, type Type } from '@nestjs/common';
import { ApiBearerAuth, ApiExtraModels, ApiHeader, ApiOperation, ApiResponse, ApiTags, getSchemaPath } from '@nestjs/swagger';
import { AuthService } from '../application/auth.service.js';
import { GenerationWorker } from '../application/generation.service.js';
import { NotebookService, publicJob } from '../application/notebook.service.js';
import { BusinessError } from '../domain/notebook.js';
import { AuthRateGuard, type AuthenticatedRequest, SessionGuard } from './security.js';
import * as D from './dto.js';

function Result(model: Type<unknown>, status = 200, page = false) {
  const value = { $ref: getSchemaPath(model) };
  return applyDecorators(ApiExtraModels(model), ApiResponse({ status, schema: { type: 'object', required: ['data'], properties: {
    data: page ? { type: 'object', required: ['items', 'nextCursor'], properties: {
      items: { type: 'array', items: value }, nextCursor: { type: 'string', nullable: true },
    } } : value,
  } } }));
}
function Failures() { return applyDecorators(...[400, 401, 404, 409, 413, 429, 500].map(status => ApiResponse({ status, type: D.ErrorResponse }))); }
function Idempotent() { return ApiHeader({ name: 'Idempotency-Key', required: true, schema: { type: 'string', format: 'uuid' },
  description: 'UUID v4. Unchanged retries return the current resource state and never reapply old writes. Recover the resource ID through /operations/{key}.' }); }
function key(value: string | undefined) {
  if (!value || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new BusinessError('VALIDATION_ERROR', 400, '需要有效的 Idempotency-Key。');
  }
  return value.toLowerCase();
}
const Id = (name: string) => Param(name, new ParseUUIDPipe({ version: '4' }), { transform: (v: string) => v.toLowerCase() });

@ApiTags('Account') @Failures() @Controller('auth')
export class AuthController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  @Post('register') @UseGuards(AuthRateGuard) @Result(D.AuthResponse, 201) @ApiOperation({ operationId: 'register' })
  async register(@Body() input: D.CredentialsDto) { return { data: await this.auth.register(input.email, input.password) }; }
  @Post('login') @HttpCode(200) @UseGuards(AuthRateGuard) @Result(D.AuthResponse) @ApiOperation({ operationId: 'login' })
  async login(@Body() input: D.CredentialsDto) { return { data: await this.auth.login(input.email, input.password) }; }
  @Get('me') @ApiBearerAuth() @UseGuards(SessionGuard) @Result(D.UserResponse) @ApiOperation({ operationId: 'currentUser' })
  me(@Req() req: AuthenticatedRequest) { return { data: req.user }; }
  @Post('logout') @HttpCode(204) @ApiBearerAuth() @UseGuards(SessionGuard) @ApiResponse({ status: 204 }) @ApiOperation({ operationId: 'logout' })
  async logout(@Req() req: AuthenticatedRequest) { await this.auth.revoke(req.token); }
}

@ApiTags('Notebook') @ApiBearerAuth() @UseGuards(SessionGuard) @Failures() @Controller()
export class NotebookController {
  constructor(@Inject(NotebookService) private readonly n: NotebookService, @Inject(GenerationWorker) private readonly worker: GenerationWorker) {}
  @Get('capabilities') @Result(D.CapabilitiesResponse) @ApiOperation({ operationId: 'getCapabilities' })
  capabilities() { return { data: { generationAvailable: this.worker.provider.available, provider: this.worker.provider.id } }; }
  @Get('operations/:key') @Result(D.OperationResponse) @ApiOperation({ operationId: 'getOperation' })
  async operation(@Req() r: AuthenticatedRequest, @Id('key') id: string) { return { data: await this.n.operation(r.user.id, id) }; }

  @Get('characters') @Result(D.CharacterResponse, 200, true) @ApiOperation({ operationId: 'listCharacters' })
  async characters(@Req() r: AuthenticatedRequest, @Query() q: D.PageDto) { return { data: await this.n.list(r.user.id, 'characters', {}, q.limit, q.cursor) }; }
  @Post('characters') @Idempotent() @Result(D.CharacterResponse, 201) @ApiOperation({ operationId: 'createCharacter' })
  async createCharacter(@Req() r: AuthenticatedRequest, @Headers('idempotency-key') k: string, @Body() b: D.CharacterDto) {
    return { data: await this.n.createCharacter(r.user.id, key(k), b) };
  }
  @Get('characters/:id') @Result(D.CharacterResponse) @ApiOperation({ operationId: 'getCharacter' })
  async character(@Req() r: AuthenticatedRequest, @Id('id') id: string) { return { data: await this.n.read(r.user.id, 'characters', id) }; }
  @Put('characters/:id') @Idempotent() @Result(D.CharacterResponse) @ApiOperation({ operationId: 'updateCharacter' })
  async updateCharacter(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() b: D.UpdateCharacterDto) {
    return { data: await this.n.updateCharacter(r.user.id, id, key(k), b) };
  }
  @Get('entries') @Result(D.EntryResponse, 200, true) @ApiOperation({ operationId: 'listUserEntries' })
  async entries(@Req() r: AuthenticatedRequest, @Query() q: D.PageDto) { return { data: await this.n.list(r.user.id, 'entries', { author: 'user' }, q.limit, q.cursor) }; }
  @Post('entries') @Idempotent() @Result(D.EntryResponse, 201) @ApiOperation({ operationId: 'createUserEntry' })
  async createEntry(@Req() r: AuthenticatedRequest, @Headers('idempotency-key') k: string, @Body() b: D.EntryDto) {
    return { data: await this.n.createEntry(r.user.id, key(k), b) };
  }
  @Get('entries/:id') @Result(D.EntryResponse) @ApiOperation({ operationId: 'getEntry' })
  async entry(@Req() r: AuthenticatedRequest, @Id('id') id: string) { return { data: await this.n.read(r.user.id, 'entries', id) }; }
  @Put('entries/:id') @Idempotent() @Result(D.EntryResponse) @ApiOperation({ operationId: 'updateUserEntry' })
  async updateEntry(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() b: D.UpdateEntryDto) {
    return { data: await this.n.updateEntry(r.user.id, id, key(k), b) };
  }
  @Get('characters/:id/entries') @Result(D.EntryResponse, 200, true) @ApiOperation({ operationId: 'listCharacterEntries' })
  async characterEntries(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    return { data: await this.n.list(r.user.id, 'entries', { characterId: id, author: 'character' }, q.limit, q.cursor, { kind: 'characters', id }) };
  }
  @Get('characters/:id/grants') @Result(D.GrantResponse, 200, true) @ApiOperation({ operationId: 'listShareGrants' })
  async grants(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    return { data: await this.n.list(r.user.id, 'grants', { characterId: id }, q.limit, q.cursor, { kind: 'characters', id }) };
  }
  @Put('characters/:id/grants/:entryId') @Idempotent() @Result(D.GrantResponse) @ApiOperation({ operationId: 'setShareGrant' })
  async share(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Id('entryId') entryId: string, @Headers('idempotency-key') k: string, @Body() b: D.ShareDto) {
    return { data: await this.n.share(r.user.id, id, entryId, key(k), b) };
  }
  @Get('characters/:id/conversations') @Result(D.ConversationResponse, 200, true) @ApiOperation({ operationId: 'listConversations' })
  async conversations(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    return { data: await this.n.list(r.user.id, 'conversations', { characterId: id }, q.limit, q.cursor, { kind: 'characters', id }) };
  }
  @Post('characters/:id/conversations') @Idempotent() @Result(D.ConversationResponse, 201) @ApiOperation({ operationId: 'createConversation' })
  async createConversation(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() b: D.ConversationDto) {
    return { data: await this.n.createConversation(r.user.id, id, key(k), b) };
  }
  @Get('conversations/:id') @Result(D.ConversationResponse) @ApiOperation({ operationId: 'getConversation' })
  async conversation(@Req() r: AuthenticatedRequest, @Id('id') id: string) { return { data: await this.n.read(r.user.id, 'conversations', id) }; }
  @Get('conversations/:id/messages') @Result(D.MessageResponse, 200, true) @ApiOperation({ operationId: 'listMessages' })
  async messages(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    return { data: await this.n.list(r.user.id, 'messages', { conversationId: id }, q.limit, q.cursor, { kind: 'conversations', id }) };
  }
  @Post('conversations/:id/messages') @HttpCode(202) @Idempotent() @Result(D.JobResponse, 202) @ApiOperation({ operationId: 'sendMessage' })
  async send(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() b: D.MessageDto) {
    return { data: publicJob(await this.n.send(r.user.id, id, key(k), b)) };
  }
  @Post('characters/:id/diary-jobs') @HttpCode(202) @Idempotent() @Result(D.JobResponse, 202) @ApiOperation({ operationId: 'generateCharacterDiary' })
  async diary(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() _b: D.EmptyDto) {
    return { data: publicJob(await this.n.generateDiary(r.user.id, id, key(k))) };
  }
  @Get('jobs/:id') @Result(D.JobResponse) @ApiOperation({ operationId: 'getGenerationJob' })
  async job(@Req() r: AuthenticatedRequest, @Id('id') id: string) { return { data: publicJob(await this.n.read(r.user.id, 'jobs', id)) }; }
  @Post('jobs/:id/retry') @HttpCode(202) @Idempotent() @Result(D.JobResponse, 202) @ApiOperation({ operationId: 'retryGenerationJob' })
  async retry(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() _b: D.EmptyDto) {
    return { data: publicJob(await this.n.retry(r.user.id, id, key(k))) };
  }
  @Get('characters/:id/jobs') @Result(D.JobResponse, 200, true) @ApiOperation({ operationId: 'listGenerationJobs' })
  async jobs(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    const page = await this.n.list(r.user.id, 'jobs', { characterId: id }, q.limit, q.cursor, { kind: 'characters', id });
    return { data: { ...page, items: page.items.map(publicJob) } };
  }
  @Get('characters/:id/memories') @Result(D.MemoryResponse, 200, true) @ApiOperation({ operationId: 'listMemories' })
  async memories(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Query() q: D.PageDto) {
    return { data: await this.n.list(r.user.id, 'memories', { characterId: id }, q.limit, q.cursor, { kind: 'characters', id }) };
  }
  @Post('characters/:id/memories') @Idempotent() @Result(D.MemoryResponse, 201) @ApiOperation({ operationId: 'createMemory' })
  async createMemory(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Headers('idempotency-key') k: string, @Body() b: D.MemoryDto) {
    return { data: await this.n.saveMemory(r.user.id, id, null, key(k), b) };
  }
  @Put('characters/:id/memories/:memoryId') @Idempotent() @Result(D.MemoryResponse) @ApiOperation({ operationId: 'updateMemory' })
  async updateMemory(@Req() r: AuthenticatedRequest, @Id('id') id: string, @Id('memoryId') memoryId: string, @Headers('idempotency-key') k: string, @Body() b: D.UpdateMemoryDto) {
    return { data: await this.n.saveMemory(r.user.id, id, memoryId, key(k), b) };
  }
}
