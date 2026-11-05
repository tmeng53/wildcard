import { AppError } from '@wildcard/errors';

/**
 * Thrown when the caller isn't in a squad they name. The same answer whether or not the squad
 * exists, so it reveals nothing about other squads. The reason is the one check-ins answer with.
 */
export class SquadNotJoinedError extends AppError {
  override readonly name = 'SquadNotJoinedError';
  readonly reason = 'SQUAD_NOT_JOINED';
  readonly status = 'PERMISSION_DENIED';

  constructor(readonly squadId: string) {
    super(`You aren’t in squad ${squadId}.`);
  }
}

/**
 * Thrown for a message the caller can't see in this squad: there is none, it was deleted, or it
 * was sent before they joined.
 */
export class ChatMessageNotFoundError extends AppError {
  override readonly name = 'ChatMessageNotFoundError';
  readonly reason = 'CHAT_MESSAGE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly messageId: string) {
    super(`There is no message ${messageId} in this chat.`);
  }
}

/** Thrown when a member deletes a message someone else wrote. */
export class NotYourMessageError extends AppError {
  override readonly name = 'NotYourMessageError';
  readonly reason = 'NOT_YOUR_MESSAGE';
  readonly status = 'PERMISSION_DENIED';

  constructor(readonly messageId: string) {
    super(`Message ${messageId} isn’t yours.`);
  }
}

/** Thrown when a member reports their own message. */
export class OwnMessageReportError extends AppError {
  override readonly name = 'OwnMessageReportError';
  readonly reason = 'OWN_MESSAGE';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('You can’t report your own message.');
  }
}

/** Thrown when a retry names a message id already used for a different message. */
export class MessageIdTakenError extends AppError {
  override readonly name = 'MessageIdTakenError';
  readonly reason = 'MESSAGE_ID_TAKEN';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly messageId: string) {
    super(`Message ${messageId} was already sent with other words.`);
  }
}
