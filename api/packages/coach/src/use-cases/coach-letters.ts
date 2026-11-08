import { NEW_YORK, wallClockAt } from '@wildcard/time-zones';
import { z } from 'zod';

import type { Coach } from '../domain/coach.js';
import { letterTask, LETTER_LIMIT, tenuresOf, type CoachLetter } from '../domain/letter.js';
import { memberOfPath, shownBody } from '../domain/memory.js';
import { instructionsOf, memoryBlock } from '../domain/prompt.js';
import { lineProblem } from '../domain/reply.js';
import type { SquadId } from '../domain/settings.js';
import { consentedOnly, rosterOf } from '../domain/squad-week.js';
import { costMicros, weekStartOf } from '../domain/wake.js';
import type {
  AiConsented,
  CoachAgent,
  CoachCatalogStore,
  CoachLetterStore,
  CoachMemoryStore,
  CoachSettingsStore,
  CoachTool,
  CoachUsageStore,
  SquadWeekSource,
} from '../ports.js';
import { offDutyWhy } from './off-duty.js';

/**
 * How long after a change of coach its letter may still be written: the app asks at once, so a
 * later ask is a stray retry, and the moment has passed.
 */
const LETTER_WINDOW_MS = 2 * 60_000;

/**
 * How long the outgoing coach has to write: the app waits 20 seconds on 今天 before the coach
 * leaves without a letter, so the run stops a little before.
 */
const WRITING_MS = 18_000;

/** A letter just saved, for the server to tell the squad in 通知. */
export type CoachLettered = (letter: CoachLetter, members: readonly string[]) => Promise<void>;

export interface CoachLetters {
  /**
   * The outgoing coach writes the next one a letter for the squad's change of coach (换教练)
   * just made, now, and it is saved: once a change, while coaching is on and the squad's coach
   * isn't off duty for the day. Answers the letter, the one written already for a retry, or
   * `undefined` when there is none (no change just made, tried before, over the cap, or the
   * coach couldn't write it in time). The caller checks the asker is the captain.
   */
  write(squad: SquadId): Promise<CoachLetter | undefined>;
}

export function createCoachLetters(deps: {
  readonly settings: CoachSettingsStore;
  readonly catalog: CoachCatalogStore;
  readonly letters: CoachLetterStore;
  readonly memory: CoachMemoryStore;
  readonly usage: CoachUsageStore;
  readonly squadWeek: SquadWeekSource;
  readonly aiConsented: AiConsented;
  readonly clock: () => Date;
  /** Without it no letter is written: there is no model to write it. */
  readonly agent?: CoachAgent;
  readonly timeZonesAt?: (
    squads: readonly SquadId[],
    moment: Date,
  ) => Promise<ReadonlyMap<string, string>>;
  readonly lettered?: CoachLettered;
}): CoachLetters {
  return {
    async write(squad) {
      const handover = await deps.letters.handover(squad);
      if (handover === undefined) return undefined;
      const written = await deps.letters.ofHandover(handover.hireEvent);
      if (written !== undefined) return written;
      const now = deps.clock();
      if (now.getTime() - handover.at.getTime() > LETTER_WINDOW_MS) return undefined;
      const { agent } = deps;
      const settings = await deps.settings.current();
      if (agent === undefined || !settings.coaching) return undefined;
      const offDuty = await offDutyWhy(
        { usage: deps.usage, clock: deps.clock, timeZonesAt: deps.timeZonesAt },
        { squad, settings },
      );
      if (offDuty !== undefined) return undefined;
      // One try a change: a second tap, or a retry while the first is writing, pays for nothing.
      if (!(await deps.letters.claim(handover))) return undefined;

      const coaches = new Map((await deps.catalog.list()).map((coach) => [coach.id, coach]));
      const from = coaches.get(handover.from);
      const to = coaches.get(handover.to);
      if (from === undefined || to === undefined) return undefined;
      const zone = (await deps.timeZonesAt?.([squad], now))?.get(squad) ?? NEW_YORK;
      const day = wallClockAt(now, zone).day;
      const task = await taskFor(deps, { squad, to, coaches, zone, day });

      let text: string | undefined;
      const run = await agent.run({
        model: settings.model,
        // The outgoing coach's own instructions, as on its wakes, so they stay cached.
        instructions: instructionsOf(settings, from),
        task,
        tools: [
          writeLetter((letter) => {
            text = letter;
          }),
        ],
        cacheKey: `coach:${from.id}`,
        timeoutMs: WRITING_MS,
      });
      // The tokens were spent whatever comes next: they count toward the squad's cap.
      await deps.usage.record({
        squad,
        coach: from.id,
        model: settings.model,
        usage: run.usage,
        costMicros: costMicros(run.usage, settings),
        at: deps.clock(),
      });
      // A letter handed in counts even if the run then ran out of time saying it was done.
      if (text === undefined) return undefined;
      await deps.letters.save({ handover, day, text });
      const letter = await deps.letters.ofHandover(handover.hireEvent);
      if (letter !== undefined && deps.lettered !== undefined) {
        const week = await deps.squadWeek({ squad, weekStart: weekStartOf(day) });
        // After the save, and never undoing it.
        await deps
          .lettered(
            letter,
            week.members.map(({ member }) => member),
          )
          .catch(() => undefined);
      }
      return letter;
    },
  };
}

/**
 * What the outgoing coach reads: who takes over, the squad's coaches so far, the members'
 * nicknames and its memory files, only of members who agreed to AI use.
 */
async function taskFor(
  deps: Pick<
    Parameters<typeof createCoachLetters>[0],
    'letters' | 'memory' | 'squadWeek' | 'aiConsented'
  >,
  {
    squad,
    to,
    coaches,
    zone,
    day,
  }: {
    readonly squad: SquadId;
    readonly to: Coach;
    readonly coaches: ReadonlyMap<string, Coach>;
    readonly zone: string;
    readonly day: string;
  },
): Promise<string> {
  const week = await deps.squadWeek({ squad, weekStart: weekStartOf(day) });
  const consented = new Set(await deps.aiConsented(week.members.map(({ member }) => member)));
  const roster = rosterOf(week);
  const nicknames = new Map(
    consentedOnly(week, consented).members.flatMap(({ member, nickname }) => {
      const name = roster.get(member);
      return name === undefined || nickname === undefined ? [] : [[name, nickname] as const];
    }),
  );
  const files = new Map<string, string>();
  for (const [path, body] of await deps.memory.files(squad)) {
    const member = memberOfPath(path);
    // A member's page only while they are in the squad and agreed to AI use.
    if (member !== undefined && !consented.has(member)) continue;
    const shown = member === undefined ? path : `people/${roster.get(member) ?? ''}.md`;
    if (shown === 'people/.md') continue;
    files.set(shown, shownBody(body, roster));
  }
  const history = tenuresOf(
    (await deps.letters.history(squad)).map(({ kind, coach, at }) => ({
      kind,
      coach,
      day: wallClockAt(at, zone).day,
    })),
  );
  return letterTask({
    to,
    history,
    names: new Map([...coaches].map(([id, coach]) => [id, coach.name])),
    nicknames,
    memory: memoryBlock(files),
  });
}

/** The one tool the outgoing coach has: handing in its letter, which is checked first. */
function writeLetter(written: (text: string) => void): CoachTool {
  const parameters = z.object({ text: z.string().describe('信的正文') });
  return {
    name: 'write_letter',
    description: `交上你的交接信，最多 ${String(LETTER_LIMIT)} 字。`,
    parameters,
    run: (input) => {
      const parsed = parameters.safeParse(input);
      if (!parsed.success) return Promise.resolve(`参数不对：${z.prettifyError(parsed.error)}`);
      const text = parsed.data.text.trim();
      const problem = lineProblem(text, LETTER_LIMIT);
      if (problem !== undefined) return Promise.resolve(`${problem}重写一封。`);
      written(text);
      return Promise.resolve('交上了。');
    },
  };
}
