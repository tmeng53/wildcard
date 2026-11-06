// Writes the holiday openings (`openings/<scene id>/`, played the day that takeover scene is on: timeline.json and the SVGs it names) into
// AvatarArt's bundled `Openings`, in the SVG subset the app reads (no text, no transforms).
// The same files go up with `put_art`, so a later opening is drawn and uploaded the same way,
// with no app release. Run: node ios/Packages/Avatar/OpeningArt/openings.mjs
import { mkdirSync, writeFileSync } from 'node:fs';

const out = new URL('../Sources/AvatarArt/Openings/', import.meta.url);
const W = 390, H = 844;
const n = (v) => Number(v.toFixed(1));

// A leaf: a pointed oval of two quadratic curves, turned by `angle` degrees.
function leaf(cx, cy, size, angle, fill) {
  const a = (angle * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
  const p = (x, y) => `${n(cx + x * c - y * s)} ${n(cy + x * s + y * c)}`;
  return `<path d="M${p(0, -size)} Q${p(size, 0)} ${p(0, size)} Q${p(-size, 0)} ${p(0, -size)} Z" fill="${fill}"/>`;
}

// The same scattering drawn `copies` times, `period` apart, so moving it down by one period
// and starting again never shows a seam.
function tiled(period, copies, draw) {
  let o = '';
  for (let k = 0; k < copies; k++) o += draw(k * period);
  return o;
}

const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">${body}</svg>\n`;

function garland(y, w) {
  let o = `<path d="M0 ${y} Q ${w / 2} ${y + 30} ${w} ${y}" stroke="#7A4A2C" stroke-width="1.6" fill="none"/>`;
  for (let i = 1; i < 14; i++) {
    const x = (i * w) / 14, k = x / w, yy = y + 30 * 2 * k * (1 - k);
    const c = ['#E6B54A', '#C9473A', '#E2783A', '#FBF7EE'][i % 4];
    o += `<path d="M${n(x - 8)} ${n(yy)} L${n(x + 8)} ${n(yy)} L${n(x)} ${n(yy + 16)} Z" fill="${c}"/>`;
  }
  return o;
}

function lights(y, lit) {
  let o = lit ? '' : `<path d="M-10 ${y} Q 97 ${y + 26} 195 ${y} Q 293 ${y + 26} 400 ${y}" stroke="#16432B" stroke-width="1.6" fill="none"/>`;
  for (let i = 0; i < 17; i++) {
    const x = -4 + i * 25, k = (x % 195) / 195, yy = y + 26 * 2 * k * (1 - k) + 5;
    if (!lit) o += `<rect x="${n(x - 3)}" y="${n(yy - 4)}" width="6" height="4" rx="1" fill="#2B2E36"/>`;
    // Every other bulb glows on its own layer, so the loop can blink it.
    if (lit === (i % 2 === 0)) o += `<ellipse cx="${n(x)}" cy="${n(yy + 4)}" rx="4.2" ry="6" fill="${['#E6B54A', '#D6403A', '#FFFFFF', '#8FD3A8'][i % 4]}"/>`;
  }
  return o;
}

const ribbon = (w, fill) => svg(w + 36, 32,
  `<path d="M0 6 h18 v26 h-18 l8 -13 Z M${w + 36} 6 h-18 v26 h18 l-8 -13 Z" fill="${fill}" fill-opacity="0.75"/>` +
  `<rect x="18" y="0" width="${w}" height="30" rx="3" fill="${fill}"/>`);

function pumpkin(x, y, k) {
  return `<ellipse cx="${n(x - 9 * k)}" cy="${n(y - 12 * k)}" rx="${n(11 * k)}" ry="${n(12 * k)}" fill="#D86A2C"/>` +
    `<ellipse cx="${n(x + 9 * k)}" cy="${n(y - 12 * k)}" rx="${n(11 * k)}" ry="${n(12 * k)}" fill="#D86A2C"/>` +
    `<ellipse cx="${n(x)}" cy="${n(y - 12 * k)}" rx="${n(11 * k)}" ry="${n(13 * k)}" fill="#E2783A"/>` +
    `<rect x="${n(x - 2 * k)}" y="${n(y - 30 * k)}" width="${n(4 * k)}" height="${n(7 * k)}" rx="${n(2 * k)}" fill="#4E8A3A"/>`;
}

function tree(x, y, k) {
  const p = (pts) => pts.map(([px, py], i) => `${i ? 'L' : 'M'}${n(x + px * k)} ${n(y + py * k)}`).join(' ') + ' Z';
  return `<path d="${p([[0, -70], [22, -36], [12, -36], [28, -10], [-28, -10], [-12, -36], [-22, -36]])}" fill="#2E7D52"/>` +
    `<rect x="${n(x - 4 * k)}" y="${n(y - 10 * k)}" width="${n(8 * k)}" height="${n(10 * k)}" fill="#7A5236"/>` +
    `<path d="${p([[0, -78], [3, -72], [9, -71], [4.5, -67], [5.5, -61], [0, -64], [-5.5, -61], [-4.5, -67], [-9, -71], [-3, -72]])}" fill="#E6B54A"/>`;
}

const key = (t, v, ease) => (ease ? { t, v, ease } : { t, v });
const track = (part, channel, keys) => ({ part, channel, keys });

function opening({ id, name, sig, wash, ground, ribbonWords, title, fall, decor, scenery, loopExtra = [] }) {
  const files = {};
  // Falling: two layers at two speeds, each a tile repeated down its period.
  files['fall-back.svg'] = svg(W, 422 * 3, tiled(422, 3, (dy) => fall(dy, 422, 12, 0.6)));
  files['fall-front.svg'] = svg(W, H * 2, tiled(H, 2, (dy) => fall(dy, H, 16, 1)));
  files['decor.svg'] = svg(W, 80, decor());
  files['ribbon.svg'] = ribbon(264, '#FFFFFF');
  files['ground.svg'] = svg(W, 234, `<path d="M0 70 Q 195 30 390 70 L390 234 L0 234 Z" fill="${ground}"/>` + scenery());
  for (const [file, body] of Object.entries(files)) writeFileSync(new URL(`${id}/${file}`, out), body);
  const words = (zhHans, en, zhHant) => ({ 'zh-Hans': zhHans, en, 'zh-Hant': zhHant });
  const layers = [
    { id: 'fallBack', x: 0, y: -422, width: W, height: 422 * 3, art: 'fall-back.svg' },
    { id: 'ground', x: 0, y: 610, width: W, height: 234, art: 'ground.svg' },
    { id: 'decor', x: 0, y: 54, width: W, height: 80, art: 'decor.svg' },
    ...loopExtra.map((l) => l.layer),
    { id: 'ribbon', x: 45, y: 262, width: 300, height: 32, art: 'ribbon.svg' },
    { id: 'ribbonWords', x: 63, y: 262, width: 264, height: 30,
      text: { words: words(ribbonWords, ribbonWords, ribbonWords), color: sig, size: 18, font: 'display' } },
    // A letter from Wildcard: to the squad by name (up to 20 characters, two lines), the greeting, then signed.
    { id: 'to', x: 20, y: 200, width: 350, height: 60,
      text: { words: words('{squad}，', '{squad},', '{squad}，'), color: '#FFFFFF', size: 22 } },
    { id: 'title', x: 20, y: 306, width: 350, height: 72, text: { words: words(...title), color: '#FFFFFF', size: 48 } },
    { id: 'from', x: 190, y: 384, width: 170, height: 28,
      text: { words: words('— 外卡', '— Wildcard', '— 外卡'), color: '#FFFFFF', size: 18 } },
    // The squad stands on the snow's crest, clear of the scenery at the edges and of 进场 below.
    { id: 'squad', x: 30, y: 420, width: 330, height: 250, squad: true },
    { id: 'fallFront', x: 0, y: -H, width: W, height: H * 2, art: 'fall-front.svg' },
  ];
  const clip = {
    version: 1, name: `${id}-opening`, duration: 3, loops: false,
    tracks: [
      ...['decor', ...loopExtra.map((l) => l.layer.id)].map((part) =>
        track(part, 'y', [key(0, -140), key(0.2, -140), key(0.9, 0, 'backOut')])),
      track('ground', 'y', [key(0, 240), key(0.5, 240), key(1.2, 0, 'easeOut')]),
      track('ribbon', 'opacity', [key(0, 0), key(0.9, 0), key(1.1, 1)]),
      track('ribbon', 'scaleX', [key(0, 0.2), key(0.9, 0.2), key(1.4, 1, 'backOut')]),
      track('ribbonWords', 'opacity', [key(0, 0), key(1.2, 0), key(1.5, 1)]),
      track('to', 'opacity', [key(0, 0), key(0.9, 0), key(1.2, 1)]),
      track('title', 'opacity', [key(0, 0), key(1.2, 0), key(1.4, 1)]),
      track('from', 'opacity', [key(0, 0), key(1.8, 0), key(2.2, 1)]),
      track('title', 'scaleX', [key(0, 0.4), key(1.2, 0.4), key(1.8, 1, 'backOut')]),
      track('title', 'scaleY', [key(0, 0.4), key(1.2, 0.4), key(1.8, 1, 'backOut')]),
      track('squad', 'y', [key(0, 300), key(1.6, 300), key(2.4, 0, 'backOut')]),
      track('fallBack', 'opacity', [key(0, 0), key(0.8, 1)]),
      track('fallFront', 'opacity', [key(0, 0), key(0.8, 1)]),
    ],
  };
  const loop = {
    version: 1, name: `${id}-loop`, duration: 8, loops: true,
    tracks: [
      track('fallBack', 'y', [key(0, 0), key(8, 422)]),
      track('fallFront', 'y', [key(0, 0), key(8, H)]),
      track('fallFront', 'x', [key(0, 0), key(2, 8, 'easeInOut'), key(4, 0, 'easeInOut'), key(6, -8, 'easeInOut'), key(8, 0, 'easeInOut')]),
      ...loopExtra.flatMap((l) => l.tracks),
    ],
  };
  const timeline = {
    version: 2, name, stage: { width: W, height: H }, background: sig,
    button: { background: sig, text: '#FFFFFF' }, layers, clip, loop,
  };
  writeFileSync(new URL(`${id}/timeline.json`, out), JSON.stringify(timeline, null, 2) + '\n');
}

// Scatter `count` bits over one tile, the same every run.
function scatter(dy, period, count, draw) {
  let o = '';
  for (let i = 0; i < count; i++) {
    const x = (i * 71 + 23) % W, y = dy + ((i * 97 + 31) % period);
    o += draw(x, y, i);
  }
  return o;
}

for (const id of ['trot', 'jingle']) mkdirSync(new URL(`${id}/`, out), { recursive: true });

opening({
  id: 'trot', name: 'Thanksgiving', sig: '#A8521F', wash: '#FBEFE6', ground: '#E8D9C5',
  ribbonWords: 'HAPPY THANKSGIVING',
  title: ['感恩节快乐！', 'Happy Thanksgiving!', '感恩節快樂！'],
  fall: (dy, period, count, k) => scatter(dy, period, count, (x, y, i) =>
    leaf(x, y, (5 + (i % 3) * 2) * k, (i * 47) % 180, ['#E6B54A', '#F6D9B0', '#E65345', '#E2783A'][i % 4])),
  decor: () => garland(6, W),
  // At the edges on the crest, beside the squad and above 进场.
  scenery: () => pumpkin(20, 74, 0.8) + pumpkin(370, 74, 0.8) +
    leaf(44, 92, 6, 30, '#C9473A') + leaf(348, 94, 6, 120, '#E6B54A'),
});

opening({
  id: 'jingle', name: 'Christmas', sig: '#1F5A3A', wash: '#E6F0EA', ground: '#FFFFFF',
  ribbonWords: 'MERRY CHRISTMAS',
  title: ['圣诞快乐！', 'Merry Christmas!', '聖誕快樂！'],
  fall: (dy, period, count, k) => scatter(dy, period, count, (x, y, i) =>
    `<circle cx="${x}" cy="${y}" r="${n((2 + (i % 3)) * k)}" fill="#FFFFFF"/>`),
  decor: () => lights(4, false),
  // At the edges on the crest, beside the squad and above 进场.
  scenery: () => tree(16, 78, 0.8) + tree(374, 78, 0.8),
  loopExtra: [{
    layer: { id: 'glow', x: 0, y: 54, width: W, height: 80, art: 'glow.svg' },
    // Half a second lit, half a second dim.
    tracks: [track('glow', 'opacity', Array.from({ length: 17 }, (_, i) => key(i / 2, i % 2 ? 0.35 : 1, i ? 'hold' : undefined)))],
  }],
});
// The lit bulbs, blinking over the string.
writeFileSync(new URL('jingle/glow.svg', out), svg(W, 80, lights(4, true)));
console.log('written');
