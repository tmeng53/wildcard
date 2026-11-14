import { AppAddress } from '@wildcard/app-routes';
import { z } from 'zod';

// 教练消息卡 (Tracy, 2026-11-12): a card admins put on members' coach pages, said by the squad's
// coach with no model writing it. There is one template; what fills it is data, its buttons'
// steps too, so a new question, a new place to send someone or a new follow-up needs no release.
// Every slot but `line` may be left out; the card shows only what is filled. Nothing is ever sent
// on its own: a message goes out only while an admin has one running.

/** A message's id, chosen by the admin who writes it, such as `enjoying-wildcard`. */
export const MessageId = z
  .string()
  .regex(/^[a-z0-9][a-z0-9-]{0,47}$/)
  .brand<'CoachMessageId'>();
export type MessageId = z.infer<typeof MessageId>;

/** A member's id. */
export const MemberId = z.uuid().brand<'CoachMessageMember'>();
export type MemberId = z.infer<typeof MemberId>;

/** A squad's id. */
export const SquadId = z.uuid().brand<'CoachMessageSquad'>();
export type SquadId = z.infer<typeof SquadId>;

/** Words in each language the app speaks: it shows the one picked in the app. */
export const Words = (max: number) =>
  z.strictObject({
    zhHans: z.string().trim().min(1).max(max),
    en: z.string().trim().min(1).max(max),
    zhHant: z.string().trim().min(1).max(max),
  });
export type Words = z.infer<ReturnType<typeof Words>>;

/** A button's id within its card, such as `yes`; a follow-up card is named by the ids tapped. */
export const ButtonId = z.string().regex(/^[a-z0-9][a-z0-9-]{0,23}$/);
export type ButtonId = z.infer<typeof ButtonId>;

/** A symbol's name as the app draws it (an SF Symbol), such as `hand.thumbsup`. */
const Symbol = z.string().regex(/^[a-z0-9][a-z0-9.]{0,63}$/);

/** Where `open` goes: a page in the app by its address (`store/powder`), or a web page. */
export const Link = z.union([
  AppAddress,
  z
    .url({ protocol: /^https$/ })
    .max(500)
    .describe('A web page, such as the App Store’s write-a-review page.'),
]);
export type Link = z.infer<typeof Link>;

/** Who stands on the card's picture with its coach. */
export const Cast = z.union([
  z.enum(['coach', 'coachAndMe', 'coachAndSquad']),
  z.strictObject({
    members: z
      .array(z.uuid())
      .min(1)
      .max(7)
      .describe('These members, by id, beside the coach (such as a workout buddy).'),
  }),
]);
export type Cast = z.infer<typeof Cast>;

/** The picture on top of the card. */
export const Stage = z.strictObject({
  cast: Cast.optional().describe(
    'Who stands with the coach: `coach` alone, `coachAndMe` (the reader), `coachAndSquad` ' +
      '(everyone, in two rows of four past four) or `{ "members": [ids] }`. Left out, `coachAndMe`.',
  ),
  move: z
    .string()
    .regex(/^[a-z][a-zA-Z0-9-]{0,47}$/)
    .optional()
    .describe('The move the coach plays, by the art’s id, such as `whistle`; left out, its idle.'),
  scene: z
    .string()
    .regex(/^[a-z][A-Za-z0-9]{0,39}$/)
    .optional()
    .describe('The scene behind them, by id; left out, the squad’s scene this week.'),
});
export type Stage = z.infer<typeof Stage>;

const CardSlots = {
  line: Words(60).describe('The big line, the only slot a card needs, such as 「喜欢外卡吗？」.'),
  body: Words(140).optional().describe('A smaller line under it.'),
  about: z
    .strictObject({
      icon: Symbol.optional(),
      name: Words(40),
      detail: Words(60).optional(),
    })
    .optional()
    .describe('What it is about: a symbol, a name and a line, such as a place.'),
  stage: Stage.optional().describe('The picture on top; left out, the coach and the reader.'),
  stars: z.literal(true).optional().describe('`true`: five stars to tap, kept as they are tapped.'),
  input: z
    .strictObject({ placeholder: Words(20).optional() })
    .optional()
    .describe('A box to type in, with the words it shows while empty.'),
  thanks: Words(40)
    .optional()
    .describe('What the card says once a button closes it, such as 「收到，谢谢你。」.'),
};

/** A step a button takes, in order. Every tap, its stars and its words are kept anyway. */
const steps = <Next extends z.ZodType>(next: Next | undefined) =>
  z.union([
    z.strictObject({
      open: Link.describe('Opens a page in the app by its address, or a web page.'),
    }),
    z.strictObject({
      feedback: z
        .enum(['problem', 'idea'])
        .describe('Sends what was typed in the card’s box as 意见反馈, a problem or an idea.'),
    }),
    z.strictObject({ close: z.literal(true).describe('Folds the card, showing its `thanks`.') }),
    ...(next === undefined
      ? []
      : [z.strictObject({ next: next.describe('Turns the card into this one.') })]),
  ]);

const button = <Next extends z.ZodType>(next: Next | undefined) =>
  z.strictObject({
    id: ButtonId.describe('The button’s id within its card, such as `yes`.'),
    label: Words(8).describe('Its words, a few characters.'),
    icon: Symbol.optional().describe('A symbol before them, such as `hand.thumbsup`.'),
    style: z
      .enum(['primary', 'outline', 'plain'])
      .optional()
      .describe('`primary` (graphite), `outline` or `plain` (words only); left out, `outline`.'),
    tap: z.array(steps(next)).min(1).max(4).describe('What a tap does, step by step.'),
  });

const card = <Next extends z.ZodType>(next: Next | undefined) =>
  z
    .strictObject({
      ...CardSlots,
      buttons: z.array(button(next)).max(3).optional().describe('0 to 3 buttons, left to right.'),
    })
    .superRefine((value, context) => {
      const buttons = value.buttons ?? [];
      if (new Set(buttons.map((each) => each.id)).size !== buttons.length) {
        context.addIssue({ code: 'custom', message: 'each button’s id once', path: ['buttons'] });
      }
      buttons.forEach((each, index) => {
        const tap: readonly object[] = each.tap;
        if (value.input === undefined && tap.some((step) => 'feedback' in step)) {
          context.addIssue({
            code: 'custom',
            message: '`feedback` sends the box’s words, so the card needs an `input`',
            path: ['buttons', index, 'tap'],
          });
        }
        if (tap.filter((step) => 'next' in step || 'close' in step).length > 1) {
          context.addIssue({
            code: 'custom',
            message: 'a tap turns to one `next` or `close`s, once',
            path: ['buttons', index, 'tap'],
          });
        }
      });
    });

/** A card three taps deep at most: a follow-up's follow-up has no `next`. */
export const LastCard = card(undefined);
export const MiddleCard = card(LastCard);
export const Card = card(MiddleCard);
export type Card = z.infer<typeof Card>;

/** One button of any card, as a reader of the tree sees it. */
export interface AnyButton {
  readonly id: ButtonId;
  readonly label: Words;
  readonly icon?: string;
  readonly style?: 'primary' | 'outline' | 'plain';
  readonly tap: readonly AnyStep[];
}

/** One step of any button. */
export type AnyStep =
  | { readonly open: Link }
  | { readonly feedback: 'problem' | 'idea' }
  | { readonly close: true }
  | { readonly next: AnyCard };

/** Any card of the tree, whatever its depth. */
export type AnyCard = Omit<z.infer<typeof LastCard>, 'buttons'> & {
  readonly buttons?: readonly AnyButton[];
};

/** The longest line a member may type, in characters. */
export const TEXT_LIMIT = 500;

/** A message as an admin writes it and it is stored: its first card, whom it is for and when. */
export const MessageValue = z
  .strictObject({
    version: z.literal(1),
    card: Card.describe('The card members get first; a button’s `next` turns it into another.'),
    members: z
      .array(z.uuid())
      .min(1)
      .max(500)
      .optional()
      .describe(
        'Only these members (by id) get it, such as admins trying it first; left out, every ' +
          'member whose squad has a coach.',
      ),
    startsAt: z.iso.datetime({ offset: true }).describe('From when members get it.'),
    endsAt: z.iso
      .datetime({ offset: true })
      .optional()
      .describe(
        'Until when a member who hasn’t opened the coach page yet still gets it; left out, until ' +
          'it is ended. A member who got it keeps the card.',
      ),
  })
  .refine(
    ({ startsAt, endsAt }) =>
      endsAt === undefined || new Date(endsAt).getTime() > new Date(startsAt).getTime(),
    { message: 'it must end after it starts', path: ['endsAt'] },
  );
export type MessageValue = z.infer<typeof MessageValue>;

/** A message as it is now, with who last saved it. */
export interface Message {
  readonly id: MessageId;
  readonly value: MessageValue;
  /** The member id of the admin who last saved it; null once they deleted their account. */
  readonly by: string | null;
  readonly savedAt: Date;
}

/** Whether `message` is for `member`: everyone, unless it names its members. */
export function isFor(message: MessageValue, member: string): boolean {
  // Member ids are uuids, which an admin may paste in either case.
  const id = member.toLowerCase();
  return (
    message.members === undefined || message.members.some((named) => named.toLowerCase() === id)
  );
}

/** Whether members who open the coach page at `now` get it. */
export function isRunning(message: MessageValue, now: Date): boolean {
  const at = now.getTime();
  return (
    new Date(message.startsAt).getTime() <= at &&
    (message.endsAt === undefined || at < new Date(message.endsAt).getTime())
  );
}

/**
 * Which card of a message's tree: the ids of the buttons tapped to reach it, `''` for the first,
 * `yes` for the one `yes` turns it into, `yes.send` one more down.
 */
export const CardPath = z
  .string()
  .regex(/^(|[a-z0-9][a-z0-9-]{0,23}(\.[a-z0-9][a-z0-9-]{0,23}){0,1})$/);
export type CardPath = z.infer<typeof CardPath>;

/** Every card of the tree by its path, the first card first. */
export function cardsOf(first: AnyCard): Map<CardPath, AnyCard> {
  const cards = new Map<CardPath, AnyCard>();
  const walk = (at: AnyCard, path: string) => {
    cards.set(CardPath.parse(path), at);
    for (const each of at.buttons ?? []) {
      for (const step of each.tap) {
        if ('next' in step) walk(step.next, path === '' ? each.id : `${path}.${each.id}`);
      }
    }
  };
  walk(first, '');
  return cards;
}

/** One part of a member's answer on one card: the button tapped, the stars, or the words typed. */
export type AnswerPart =
  | { readonly part: 'tap'; readonly button: ButtonId }
  | { readonly part: 'stars'; readonly stars: number }
  | { readonly part: 'text'; readonly text: string };

/** A member's answer on one card so far: each part once, the first standing. */
export interface Answered {
  readonly tap?: ButtonId;
  readonly stars?: number;
  readonly text?: string;
}

/**
 * Whether `part` may answer the card at `path` now, given what the member `answered` on every
 * card: the card must be reached (its button tapped on the card before it), and take that part.
 * Nil when it may, else why not.
 */
export function refusal(
  message: MessageValue,
  {
    answered,
    path,
    part,
  }: {
    readonly answered: ReadonlyMap<CardPath, Answered>;
    readonly path: CardPath;
    readonly part: AnswerPart;
  },
): string | undefined {
  const cards = cardsOf(message.card);
  const at = cards.get(path);
  if (at === undefined) return 'no such card';
  if (path !== '') {
    const ids = path.split('.');
    const before = CardPath.parse(ids.slice(0, -1).join('.'));
    if (answered.get(before)?.tap !== ids.at(-1)) return 'its button wasn’t tapped';
  }
  switch (part.part) {
    case 'tap':
      return (at.buttons ?? []).some((each) => each.id === part.button)
        ? undefined
        : 'no such button';
    case 'stars':
      if (at.stars !== true) return 'it has no stars';
      return Number.isInteger(part.stars) && part.stars >= 1 && part.stars <= 5
        ? undefined
        : 'one to five stars';
    case 'text':
      return at.input === undefined ? 'it has no box to type in' : undefined;
  }
}
