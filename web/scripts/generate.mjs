// Writes the site's generated files. The site and the app share one character art and one
// wordmark font, so those come from the app's own sources:
//   public/home/characters.js       the rig, the five looks drawn from the app's SVG parts, the clips
//   public/join/characters.js       the rig, all of the app's art and the idles, for the invite page
//                                   to dress each member's look as the API sends it
//   public/fonts/                   Barlow Condensed ExtraBold and its license, from DesignSystemUI
//   public/{,zh/,zh-hant/}index.html  the home page in each language, from pages/home.html
// `node scripts/generate.mjs --verify` fails while a written file is stale.
import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dress } from '../public/character/dress.js';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const ios = join(web, '..', 'ios', 'Packages');
const art = join(ios, 'Avatar', 'Sources', 'AvatarArt', 'Placeholder');
const fonts = join(ios, 'DesignSystem', 'Sources', 'DesignSystemUI', 'Resources', 'Fonts');
const verify = process.argv.includes('--verify');

const json = (path) => JSON.parse(readFileSync(path, 'utf8'));
const svgInner = (path) =>
  readFileSync(path, 'utf8')
    .replace(/<\/?svg[^>]*>/g, '')
    .trim();
const list = (dir) => readdirSync(dir).sort();

const rig = json(join(art, 'rig.json'));

// All of the app's art, as public/character/dress.js takes it.
const wardrobe = {
  parts: rig.parts,
  defaults: rig.defaults,
  skin: rig.skin,
  variants: {},
  art: {},
  tones: {},
  holds: {},
};
for (const file of list(join(art, 'art', 'base')).filter((f) => f.endsWith('.svg')))
  wardrobe.art[`base/${basename(file, '.svg')}`] = svgInner(join(art, 'art', 'base', file));
for (const slot of list(join(art, 'art')).filter((s) => s !== 'base')) {
  wardrobe.variants[slot] = list(join(art, 'art', slot));
  for (const variant of wardrobe.variants[slot]) {
    const dir = join(art, 'art', slot, variant);
    for (const file of list(dir).filter((f) => f.endsWith('.svg')))
      wardrobe.art[`${slot}/${variant}/${basename(file, '.svg')}`] = svgInner(join(dir, file));
    if (existsSync(join(dir, 'tones.json'))) {
      const { base, shades } = json(join(dir, 'tones.json'));
      wardrobe.tones[`${slot}/${variant}`] = { base, shades: shades ?? [] };
    }
    if (existsSync(join(dir, 'hold.json')))
      wardrobe.holds[`${slot}/${variant}`] = json(join(dir, 'hold.json')).level;
  }
}

const rigParts = rig.parts.map(({ id, parent, pivot, opacity }) => ({
  id,
  parent: parent ?? null,
  pivot,
  opacity: opacity ?? 1,
}));
const idles = (personas) =>
  Object.fromEntries(personas.map((p) => [p, json(join(art, 'clips', p, 'idle.json'))]));

const { cast } = json(join(web, 'character', 'cast.json'));
const personas = [...new Set(cast.map((m) => m.persona))].sort();
const clip = (path) => json(path);
const moves = ['warmup', 'stretch', 'pump', 'wave'];

const bundle = {
  version: 1,
  parts: rigParts,
  cast: cast.map(({ id, zh, zhHant, en, persona, look, colors }) => ({
    id,
    zh,
    zhHant,
    en,
    persona,
    art: dress(wardrobe, look, colors),
  })),
  idle: idles(personas),
  cheer: Object.fromEntries(personas.map((p) => [p, clip(join(art, 'clips', p, 'cheer.json'))])),
  moves: Object.fromEntries(
    moves.map((m) => [m, clip(join(web, 'character', 'moves', `${m}.json`))]),
  ),
};

// The invite page dresses any look the API sends, so it gets the whole wardrobe and every idle.
const allPersonas = list(join(art, 'clips'));
const joinBundle = {
  version: 1,
  ...wardrobe,
  parts: rig.parts.map((part, i) => ({ ...rigParts[i], layers: part.layers ?? [] })),
  personas: allPersonas,
  idle: idles(allPersonas),
};

// Apple's logo on the button that opens the App Store (the same glyph the invite page draws).
const APPLE_LOGO =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>';

// The home page's words per language; the template marks each slot {{name}}.
const pages = [
  {
    file: 'index.html',
    lang: 'en',
    path: '/',
    title: 'Wildcard: become everyday athletes',
    description: 'Check in with your squad every day. Become everyday athletes.',
    languageLabel: 'Language',
    headlineLabel: 'Wildcard',
    cn: '',
    slogan: 'Become everyday athletes',
    button: 'Get your wildcard',
    legal: '/',
    privacy: 'Privacy',
    terms: 'Terms',
  },
  {
    file: 'zh/index.html',
    lang: 'zh-Hans',
    path: '/zh/',
    title: '外卡 Wildcard：人人都是运动员',
    description: '和朋友组队，每天打卡。人人都是运动员。',
    languageLabel: '语言',
    headlineLabel: 'Wildcard 外卡',
    cn: '<span class="cn" data-settle>外卡</span>',
    slogan: '人人都是运动员',
    button: '领取外卡',
    legal: '/zh/',
    privacy: '隐私政策',
    terms: '使用条款',
  },
  {
    file: 'zh-hant/index.html',
    lang: 'zh-Hant',
    path: '/zh-hant/',
    title: '外卡 Wildcard：人人都是運動員',
    description: '揪朋友組隊，每天打卡。人人都是運動員。',
    languageLabel: '語言',
    headlineLabel: 'Wildcard 外卡',
    cn: '<span class="cn" data-settle>外卡</span>',
    slogan: '人人都是運動員',
    button: '領取外卡',
    legal: '/zh-hant/',
    privacy: '隱私權政策',
    terms: '使用條款',
  },
];
const template = readFileSync(join(web, 'pages', 'home.html'), 'utf8');
function page(words) {
  const current = (lang) => (words.lang === lang ? ' aria-current="page"' : '');
  const slots = {
    ...words,
    apple: APPLE_LOGO,
    currentHans: current('zh-Hans'),
    currentHant: current('zh-Hant'),
    currentEn: current('en'),
  };
  // The note goes after the doctype: anything before it puts browsers in quirks mode.
  return template
    .replace(/\{\{(\w+)\}\}/g, (_, name) => {
      if (!(name in slots)) throw new Error(`pages/home.html: no words for {{${name}}}`);
      return slots[name];
    })
    .replace(
      '<!doctype html>\n',
      '<!doctype html>\n<!-- Written by `pnpm --dir web generate` from pages/home.html; never edit by hand. -->\n',
    );
}

const outputs = [
  ...pages.map((words) => [join(web, 'public', words.file), page(words)]),
  [
    join(web, 'public', 'home', 'characters.js'),
    "// Written by `pnpm --dir web generate` from the app's art; never edit by hand.\n" +
      `window.WILDCARD_CHARACTERS = ${JSON.stringify(bundle)};\n`,
  ],
  [
    join(web, 'public', 'join', 'characters.js'),
    "// Written by `pnpm --dir web generate` from the app's art; never edit by hand.\n" +
      `window.WILDCARD_CHARACTERS = ${JSON.stringify(joinBundle)};\n`,
  ],
  [
    join(web, 'public', 'fonts', 'BarlowCondensed-ExtraBold.ttf'),
    readFileSync(join(fonts, 'BarlowCondensed-ExtraBold.ttf')),
  ],
  [join(web, 'public', 'fonts', 'OFL.txt'), readFileSync(join(fonts, 'OFL.txt'))],
];

let stale = 0;
for (const [path, content] of outputs) {
  const bytes = Buffer.from(content);
  if (verify) {
    if (!existsSync(path) || !readFileSync(path).equals(bytes)) {
      console.error(`stale: ${path} (run pnpm --dir web generate)`);
      stale += 1;
    }
  } else {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, bytes);
  }
}
if (stale > 0) process.exit(1);
