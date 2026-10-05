export type Clock = () => Date;
export class BusinessError extends Error {
  constructor(public readonly code: string, public readonly status: number, message: string) { super(message); }
}
export interface Character {
  id: string; name: string; background: string; style: string; revision: number; contextVersion: number;
  createdAt: string; updatedAt: string;
}
export interface Entry {
  id: string; author: 'user' | 'character'; characterId: string | null; title: string; body: string;
  revision: number; contextVersion: number | null; createdAt: string; updatedAt: string;
}
export interface Grant {
  id: string; characterId: string; entryId: string; entryRevision: number; active: boolean; revision: number;
  createdAt: string; updatedAt: string;
}
export interface Conversation { id: string; characterId: string; entryId: string | null; createdAt: string }
export interface Message {
  id: string; characterId: string; conversationId: string; role: 'user' | 'assistant'; body: string;
  sequence: number; contextVersion: number; jobId: string | null; createdAt: string;
}
export interface Source { entryId: string; revision: number }
export interface Memory {
  id: string; characterId: string; body: string; sources: Source[]; active: boolean; revision: number;
  createdAt: string; updatedAt: string;
}
export type JobStatus = 'pending' | 'running' | 'succeeded' | 'failed' | 'cancelled';
export interface Job {
  id: string; characterId: string; conversationId: string | null; userMessageId: string | null;
  kind: 'reply' | 'diary'; status: JobStatus; contextVersion: number; attempt: number;
  leaseUntil: string | null; runToken: string | null; resultId: string | null; errorCode: string | null;
  sources: Source[]; createdAt: string; updatedAt: string;
}
export interface Receipt {
  id: string; operation: string; fingerprint: string; resourceKind: ResourceKind; resourceId: string; createdAt: string;
}
export interface Entities {
  characters: Character; entries: Entry; grants: Grant; conversations: Conversation;
  messages: Message; memories: Memory; jobs: Job; receipts: Receipt;
}
export type ResourceKind = Exclude<keyof Entities, 'receipts'>;
export interface Cursor { id: string; createdAt: string; scope: string; sequence?: number }
export interface NotebookTransaction {
  get<K extends keyof Entities>(kind: K, id: string): Promise<Entities[K] | null>;
  list<K extends keyof Entities>(kind: K, filter: Partial<Entities[K]>, limit: number, before?: Cursor): Promise<Entities[K][]>;
  save<K extends keyof Entities>(kind: K, value: Entities[K]): Promise<void>;
}
export interface NotebookRepository {
  transact<T>(owner: string, write: boolean, action: (tx: NotebookTransaction) => Promise<T>): Promise<T>;
  pendingOwners(limit: number): Promise<string[]>;
}
export interface ModelContext {
  kind: Job['kind']; character: { name: string; background: string; style: string };
  sharedEntries: { id: string; revision: number; title: string; body: string }[];
  memories: { body: string; sources: Source[] }[];
  characterEntries: { id: string; title: string; body: string }[];
  messages: { role: Message['role']; body: string }[];
  instruction: string;
}
export interface ModelProvider {
  readonly id: string;
  readonly available: boolean;
  generate(context: ModelContext, signal: AbortSignal): Promise<{ body: string }>;
}
