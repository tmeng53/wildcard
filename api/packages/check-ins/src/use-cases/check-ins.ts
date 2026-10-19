import type { CheckInRecord, MemberId } from '../domain/check-in.js';
import type { DayRange } from '../domain/day-range.js';
import type { CheckInStore, Clock } from '../ports.js';
import { listMyCheckIns } from './check-ins/list-my-check-ins.js';
import {
  listSquadCheckIns,
  type ListSquadCheckInsInput,
} from './check-ins/list-squad-check-ins.js';
import {
  saveCheckIn,
  type SaveCheckInInput,
  type SavedCheckIn,
} from './check-ins/save-check-in.js';

/** Daily check-ins: saving them and reading them back. */
export interface CheckIns {
  save(input: SaveCheckInInput): Promise<SavedCheckIn>;
  listForSquad(input: ListSquadCheckInsInput): Promise<CheckInRecord[]>;
  listMine(input: { readonly member: MemberId; readonly days: DayRange }): Promise<CheckInRecord[]>;
}

export function createCheckIns(deps: {
  readonly store: CheckInStore;
  readonly clock: Clock;
}): CheckIns {
  return {
    save: (input) => saveCheckIn(deps, input),
    listForSquad: (input) => listSquadCheckIns(deps, input),
    listMine: (input) => listMyCheckIns(deps, input),
  };
}
