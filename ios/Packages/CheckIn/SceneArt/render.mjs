// Renders the home scenes' art from the approved simple home design's source (scenes.js,
// 2026-10-20) into the PNGs CheckInUI draws: per scene the day art, the night overlay (dark
// tint and lamps), the lamp tubes alone (which flicker on as the lights come on, 开灯) and,
// where the venue has one, the front layer people stand behind (the tennis net). Run: node ios/Packages/CheckIn/SceneArt/render.mjs (needs Playwright's Chromium).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? '/opt/node-tools/node_modules/playwright-core');
const out = join(here, '../Sources/CheckInUI/Resources/Scenes');
mkdirSync(out, { recursive: true });

const source = readFileSync(join(here, 'scenes.js'), 'utf8');
const scenes = new Function(`${source}; return { SCENES, liftScene };`)();
const fonts = join(here, '../../DesignSystem/Sources/DesignSystemUI/Resources/Fonts');
const face = (file, weight) =>
  `@font-face{font-family:'Barlow Condensed';font-weight:${weight};src:url(data:font/ttf;base64,${readFileSync(join(fonts, file)).toString('base64')})}`;
const css = face('BarlowCondensed-SemiBold.ttf', 600) + face('BarlowCondensed-ExtraBold.ttf', 800);
const svg = body => `<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" viewBox="0 0 390 844"><style>${css}</style>${body}</svg>`;
// The night tint from the design.
const night = '<rect width="390" height="844" fill="#0E1424" opacity=".58"/>';

const names = { track: 'track', pool: 'pool', gym: 'gym', tennis: 'tennis', climb: 'climbing' };
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3 });
async function shoot(name, body, transparent) {
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg(body)}</body></html>`);
  await page.evaluate(() => document.fonts.ready);
  writeFileSync(join(out, `${name}@3x.png`), await page.screenshot({ omitBackground: transparent, clip: { x: 0, y: 0, width: 390, height: 844 } }));
}
for (const [key, name] of Object.entries(names)) {
  const scene = scenes.liftScene(scenes.SCENES[key]());
  await shoot(`${name}-day`, scene.bg, false);
  await shoot(`${name}-night`, night + scene.lamps + scene.lampsTop, true);
  await shoot(`${name}-lamps`, scene.lampsTop, true);
  for (const [i, front] of scene.fronts.entries()) await shoot(`${name}-front-${i}`, front.svg, true);
  console.log(name, scene.fronts.map(front => front.y));
}
await browser.close();
