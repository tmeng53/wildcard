// Writes the home page's generated files. The site and the app share one character art and one
// wordmark font, so those come from the app's own sources:
//   public/home/characters.js       the rig, the five looks drawn from the app's SVG parts, the clips
//   public/fonts/                   Barlow Condensed ExtraBold and its license, from DesignSystemUI
//   public/{,zh/,zh-hant/}index.html  the home page in each language, from pages/home.html
// `node scripts/generate.mjs --verify` fails while a written file is stale.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

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
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const replaceAllCaseless = (text, from, to) => text.replace(new RegExp(escape(from), 'gi'), to);

// A shade keeps its relation to the base color: each channel scales by shade/base.
const channels = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
function shadeTo(base, shade, color) {
  const [b, s, c] = [channels(base), channels(shade), channels(color)];
  return (
    '#' +
    c
      .map((n, i) => Math.max(0, Math.min(255, Math.round(n * (s[i] / Math.max(b[i], 1))))))
      .map((n) => n.toString(16).toUpperCase().padStart(2, '0'))
      .join('')
  );
}

const rig = json(join(art, 'rig.json'));

// One look's art: a string of SVG per rig part, back to front, as the app's player draws it.
function draw(member) {
  const look = { ...rig.defaults, ...member.look };
  return rig.parts.map((part) =>
    (part.layers ?? [])
      .map(({ slot, art: name }) => {
        if (slot !== undefined && !look[slot]) return '';
        const path =
          slot === undefined
            ? join(art, 'art', 'base', `${name}.svg`)
            : join(art, 'art', slot, look[slot], `${name}.svg`);
        if (!existsSync(path)) return '';
        let svg = svgInner(path);
        if (slot === 'shoes') {
          for (const [from, to] of member.shoes) svg = svg.replaceAll(from, to);
        } else if (slot in member.colors) {
          const tones = json(join(art, 'art', slot, look[slot], 'tones.json'));
          const color = member.colors[slot];
          for (const shade of tones.shades ?? [])
            svg = replaceAllCaseless(svg, shade, shadeTo(tones.base, shade, color));
          svg = replaceAllCaseless(svg, tones.base, color);
        }
        return svg;
      })
      .join(''),
  );
}

const { cast } = json(join(web, 'character', 'cast.json'));
const personas = [...new Set(cast.map((m) => m.persona))].sort();
const clip = (path) => json(path);
const moves = ['warmup', 'stretch', 'pump', 'wave'];

const bundle = {
  version: 1,
  parts: rig.parts.map(({ id, parent, pivot, opacity }) => ({
    id,
    parent: parent ?? null,
    pivot,
    opacity: opacity ?? 1,
  })),
  cast: cast.map(({ id, zh, zhHant, en, persona, ...member }) => ({
    id,
    zh,
    zhHant,
    en,
    persona,
    art: draw(member),
  })),
  idle: Object.fromEntries(personas.map((p) => [p, clip(join(art, 'clips', p, 'idle.json'))])),
  cheer: Object.fromEntries(personas.map((p) => [p, clip(join(art, 'clips', p, 'cheer.json'))])),
  moves: Object.fromEntries(
    moves.map((m) => [m, clip(join(web, 'character', 'moves', `${m}.json`))]),
  ),
  dumbbell: svgInner(join(art, 'art', 'prop', 'dumbbell', 'propR.svg')),
};

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
