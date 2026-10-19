import type { CheckInId, CheckInRecord, MemberId } from '../domain/check-in.js';
import type { DayRange } from '../domain/day-range.js';
import type { Reaction } from '../domain/reaction.js';
import type { CheckInStore, Clock, PhotoFiles, ReactionStore } from '../ports.js';
import { listMyCheckIns } from './check-ins/list-my-check-ins.js';
import { listReactions } from './check-ins/list-reactions.js';
import {
  listSquadCheckIns,
  type ListSquadCheckInsInput,
} from './check-ins/list-squad-check-ins.js';
import {
  reactToCheckIn,
  type ReactToCheckInInput,
  type Reacted,
} from './check-ins/react-to-check-in.js';
import { removeReaction } from './check-ins/remove-reaction.js';
import {
  saveCheckIn,
  type SaveCheckInInput,
  type SavedCheckIn,
} from './check-ins/save-check-in.js';

/** Daily check-ins: saving them, reading them back, and teammates' reactions on them. */
export interface CheckIns {
  save(input: SaveCheckInInput): Promise<SavedCheckIn>;
  listForSquad(input: ListSquadCheckInsInput): Promise<CheckInRecord[]>;
  listMine(input: { readonly member: MemberId; readonly days: DayRange }): Promise<CheckInRecord[]>;
  react(input: ReactToCheckInInput): Promise<Reacted>;
  removeReaction(input: { readonly checkIn: CheckInId; readonly member: MemberId }): Promise<void>;
  listReactions(input: {
    readonly checkIn: CheckInId;
    readonly viewer: MemberId;
  }): Promise<Reaction[]>;
}

export function createCheckIns(deps: {
  readonly store: CheckInStore;
  readonly reactions: ReactionStore;
  readonly photos: PhotoFiles;
  readonly clock: Clock;
}): CheckIns {
  return {
    save: (input) => saveCheckIn(deps, input),
    listForSquad: (input) => listSquadCheckIns(deps, input),
    listMine: (input) => listMyCheckIns(deps, input),
    react: (input) => reactToCheckIn(deps, input),
    removeReaction: (input) => removeReaction(deps, input),
    listReactions: (input) => listReactions(deps, input),
  };
}
