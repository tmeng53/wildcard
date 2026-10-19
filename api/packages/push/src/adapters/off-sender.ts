import type { PushSender } from '../ports.js';

/** The sender until there is an APNs key: it sends nothing and says so. */
export function createOffSender(): PushSender {
  return { send: () => Promise.resolve('off') };
}
