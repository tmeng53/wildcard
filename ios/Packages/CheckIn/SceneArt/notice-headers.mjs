// Renders the header art of a celebration broadcast (the approved pre-holiday notice, holiday
// stores design v10, 2026-11-04) into the PNGs CheckInUI draws at the top of its card: the
// backdrop, its garland or lights and the ribbon, without the member, whom the app draws on it
// wearing what the notice gives. One per scene the notice takes its colours from, named
// `<scene>-notice@3x.png`; an admin can put a new one at `scenes/<scene>-notice@3x.png`.
// Run: node ios/Packages/CheckIn/SceneArt/notice-headers.mjs (needs Playwright's Chromium).
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? 'playwright');
const out = join(here, '../Sources/CheckInUI/Resources/Scenes');
mkdirSync(out, { recursive: true });

const fonts = join(here, '../../DesignSystem/Sources/DesignSystemUI/Resources/Fonts');
const css = `@font-face{font-family:'Barlow Condensed';font-weight:700;src:url(data:font/ttf;base64,${readFileSync(join(fonts, 'BarlowCondensed-ExtraBold.ttf')).toString('base64')})}`;

const W = 346;
const H = 176;
// The scenes' signature colours (the scene catalog's), the ribbon's fill.
const scenes = {
  trot: { signature: '#A8521F', label: 'THANKSGIVING', sky: '#F7EBDD', ground: '#EFE2CF' },
  jingle: { signature: '#1F5A3A', label: 'CHRISTMAS', sky: '#E4ECF2', ground: '#FFFFFF' },
};

const lights = (y) => {
  let o = `<path d="M-10 ${y} Q 97 ${y + 26} 195 ${y} Q 293 ${y + 26} 400 ${y}" stroke="#16432B" stroke-width="1.6" fill="none"/>`;
  for (let i = 0; i < 17; i++) {
    const x = -4 + i * 25;
    const k = (x % 195) / 195;
    const yy = y + 26 * 2 * k * (1 - k) + 5;
    const on = i % 3 !== 0;
    o += `<rect x="${(x - 3).toFixed(1)}" y="${(yy - 4).toFixed(1)}" width="6" height="4" rx="1" fill="#2B2E36"/><ellipse cx="${x.toFixed(1)}" cy="${(yy + 4).toFixed(1)}" rx="4.2" ry="6" fill="${['#E6B54A', '#D6403A', '#FFFFFF', '#8FD3A8'][i % 4]}" fill-opacity="${on ? 1 : 0.45}"/>`;
  }
  return o;
};
const garland = (y, w) => {
  let o = `<path d="M0 ${y} Q ${w / 2} ${y + 30} ${w} ${y}" stroke="#7A4A2C" stroke-width="1.6" fill="none"/>`;
  for (let i = 1; i < 14; i++) {
    const x = (i * w) / 14;
    const k = x / w;
    const yy = y + 30 * 2 * k * (1 - k);
    o += `<path d="M${(x - 8).toFixed(1)} ${yy.toFixed(1)} L${(x + 8).toFixed(1)} ${yy.toFixed(1)} L${x.toFixed(1)} ${(yy + 16).toFixed(1)} Z" fill="${['#E6B54A', '#C9473A', '#E2783A', '#FBF7EE'][i % 4]}"/>`;
  }
  return o;
};
const ribbon = (cx, y, w, label, fill, ink) =>
  `<path d="M${cx - w / 2 - 18} ${y + 6} h18 v26 h-18 l8 -13 Z M${cx + w / 2 + 18} ${y + 6} h-18 v26 h18 l-8 -13 Z" fill="${fill}" fill-opacity=".75"/>` +
  `<rect x="${cx - w / 2}" y="${y}" width="${w}" height="30" rx="3" fill="${fill}"/>` +
  `<text x="${cx}" y="${y + 22}" text-anchor="middle" font-family="Barlow Condensed" font-weight="700" font-size="18" letter-spacing="2" fill="${ink}">${label}</text>`;

function header(key) {
  const s = scenes[key];
  let o = `<rect width="${W}" height="${H}" fill="${s.sky}"/>`;
  if (key === 'jingle') {
    o += Array.from({ length: 22 }, (_, i) => `<circle cx="${(i * 61) % W}" cy="${((i * 37) % 190) - 8}" r="${1.4 + (i % 3) * 0.6}" fill="#FFFFFF"/>`).join('');
  }
  o += `<path d="M0 150 Q 173 132 346 150 L346 176 L0 176 Z" fill="${s.ground}"/>`;
  o += key === 'trot' ? garland(6, W) : lights(4);
  if (key === 'trot') {
    o += [[30, 140, '#E2783A'], [300, 146, '#C9473A'], [70, 160, '#E6B54A'], [270, 162, '#E2783A']]
      .map(([x, y, c]) => `<path d="M${x} ${y - 6} q6 6 0 12 q-6 -6 0 -12 Z" fill="${c}"/>`)
      .join('');
    o += '<g transform="translate(286 150) scale(.9)"><ellipse cx="-9" cy="-12" rx="11" ry="12" fill="#D86A2C"/><ellipse cx="9" cy="-12" rx="11" ry="12" fill="#D86A2C"/><ellipse cx="0" cy="-12" rx="11" ry="13" fill="#E2783A"/><rect x="-2" y="-30" width="4" height="7" rx="2" fill="#4E8A3A"/></g>';
  } else {
    o += '<g transform="translate(296 150)"><path d="M0 -70 L22 -36 L12 -36 L28 -10 L-28 -10 L-12 -36 L-22 -36 Z" fill="#2E7D52"/><rect x="-4" y="-10" width="8" height="10" fill="#7A5236"/><path d="M0 -78 l3 6 6 1 -4.5 4 1 6 -5.5 -3 -5.5 3 1 -6 -4.5 -4 6 -1 Z" fill="#E6B54A"/></g><g transform="translate(48 150)"><rect x="-16" y="-24" width="24" height="24" rx="2" fill="#D6403A"/><rect x="-6" y="-24" width="4" height="24" fill="#E6B54A"/><rect x="8" y="-16" width="18" height="16" rx="2" fill="#2E7D52"/><rect x="15" y="-16" width="4" height="16" fill="#FFFFFF"/></g>';
  }
  o += ribbon(173, 30, 150, s.label, s.signature, '#FFFFFF');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><style>${css}</style>${o}</svg>`;
}

const only = process.env.ONLY;
const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 3 });
for (const key of Object.keys(scenes)) {
  if (only && only !== key) continue;
  await page.setContent(`<html><body style="margin:0">${header(key)}</body></html>`);
  await page.evaluate(() => document.fonts.ready);
  writeFileSync(join(out, `${key}-notice@3x.png`), await page.screenshot({ clip: { x: 0, y: 0, width: W, height: H } }));
  console.log(key);
}
await browser.close();
