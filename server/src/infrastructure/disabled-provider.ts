import type { ModelContext, ModelProvider } from '../domain/notebook.js';

/** No fake replies or external requests when the user has not selected a provider. */
export class DisabledProvider implements ModelProvider {
  readonly id = 'disabled'; readonly available = false;
  async generate(_context: ModelContext, _signal: AbortSignal): Promise<{ body: string }> {
    throw new Error('Provider is not configured');
  }
}
