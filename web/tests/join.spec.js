// The invite page (/join/<code>) against a stubbed API: what it says for each answer, the squad's
// own characters in the 排队入场 queue, and its layout from a small phone to a desktop.
import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';

const API = 'https://api.wildcardsquad.com/public/squad-invites/';
const APP_STORE = 'https://apps.apple.com/app/id6826015677';
// Looks as the API sends them, from the home page's cast.
const { cast } = JSON.parse(readFileSync(new URL('../character/cast.json', import.meta.url)));
const looks = cast.map(({ persona, look, colors }) => ({ persona, variants: look, colors }));
const squad = (count, more = {}) => ({
  version: 1,
  name: '周末网球',
  memberCount: count,
  full: false,
  looks: Array.from({ length: count }, (_, i) => looks[i % looks.length]),
  ...more,
});

/** Answers the page's lookup with `status` and `body`, and records the codes it asked for. */
async function stub(page, status, body) {
  const asked = [];
  await page.route(`${API}*`, (route) => {
    asked.push(decodeURIComponent(route.request().url().slice(API.length)));
    return route.fulfill({
      status,
      contentType: status === 200 ? 'application/json' : 'application/problem+json',
      body: JSON.stringify(body ?? { reason: 'X' }),
    });
  });
  return asked;
}

const overlaps = (a, b) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

test('shows the squad, its size and the code, and the button opens the App Store', async ({
  page,
}) => {
  const asked = await stub(page, 200, squad(3));
  await page.goto('/join/k7m2qx9p?lang=zh-Hans');
  await expect(page.locator('#name')).toHaveText('周末网球');
  await expect(page.locator('#eyebrow')).toHaveText('你被邀请加入');
  await expect(page.locator('#sub')).toHaveText('3 名队员，就差你了');
  await expect(page.locator('#get')).toHaveText('加入小队');
  await expect(page.locator('#get')).toHaveAttribute('href', APP_STORE);
  await expect(page.locator('#code-value')).toHaveText('K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(3);
  await expect(page).toHaveTitle('加入「周末网球」· 外卡');
  expect(asked).toStrictEqual(['k7m2qx9p']);
});

test('speaks Traditional Chinese and English, and links the legal pages in each', async ({
  page,
}) => {
  await stub(page, 200, squad(2));
  await page.goto('/join/K7M2QX9P?lang=zh-Hant');
  await expect(page.locator('#sub')).toHaveText('2 名隊員，就差你了');
  await expect(page.locator('#privacy')).toHaveAttribute('href', '/zh-hant/privacy');
  await expect(page.locator('.wc-lang [aria-current="page"]')).toHaveText('繁體');
  await page.locator('.wc-lang a[lang="en"]').click();
  await expect(page).toHaveURL(/\/join\/K7M2QX9P\?lang=en$/);
  await expect(page.locator('#sub')).toHaveText("2 in. You're next.");
  await expect(page.locator('#get')).toHaveText('Join the squad');
  await expect(page.locator('#terms')).toHaveAttribute('href', '/terms');
});

test('a full squad says so and offers the app without the code', async ({ page }) => {
  await stub(page, 200, squad(8, { full: true }));
  await page.goto('/join/K7M2QX9P?lang=en');
  await expect(page.locator('#sub')).toHaveText("This squad's full.");
  await expect(page.locator('#get')).toHaveText('Get your wildcard');
  await expect(page.locator('#code')).toBeHidden();
});

for (const [status, name] of [
  [404, '这个邀请码不对'],
  [429, '打开太多次了'],
  [500, '暂时连不上'],
]) {
  test(`answers ${status} plainly, with no squad`, async ({ page }) => {
    await stub(page, status);
    await page.goto('/join/ZZZZZZZZ?lang=zh-Hans');
    await expect(page.locator('#name')).toHaveText(name);
    await expect(page.locator('#get')).toHaveText('领取外卡');
    await expect(page.locator('#eyebrow')).toBeHidden();
    await expect(page.locator('.lineup svg')).toHaveCount(0);
  });
}

test('leaves out a look whose body this art doesn’t have, and ignores slots and hair it doesn’t know', async ({
  page,
}) => {
  const odd = [
    { persona: 'ninja', variants: { body: 'peach', hair: 'mohawk', constructor: 'x' }, colors: {} },
    { persona: 'shy', variants: { body: 'dragon' }, colors: {} },
  ];
  await stub(page, 200, squad(2, { looks: odd }));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(1);
  expect(await page.locator('.lineup svg > g').innerHTML()).not.toBe('');
});

test('a held prop takes the wearer’s hand, and a prop that hangs keeps level as the arm swings', async ({
  page,
}) => {
  await stub(page, 200, squad(1));
  await page.goto('/join/K7M2QX9P');
  const { grips, level } = await page.evaluate(async () => {
    const { dress, leveled } = await import('/character/dress.js');
    const C = window.WILDCARD_CHARACTERS;
    const gripR = C.parts.findIndex(({ id }) => id === 'gripR');
    const grip = (body) => dress(C, { body, prop: 'bottle' })[gripR];
    return {
      grips: { peach: grip('peach'), cat: grip('cat') },
      level: { bottle: leveled(C, { prop: 'bottle' }), dumbbell: leveled(C, { prop: 'dumbbell' }) },
    };
  });
  // The fist is drawn in the rig's skin and repainted to each body's own hand.
  expect(grips.peach).toContain('#F5CDAE');
  expect(grips.cat).toContain('#F2A65A');
  expect(grips.cat).not.toContain('#F5CDAE');
  // The tumbler hangs level from the arm; the dumbbell is gripped and swings with it.
  expect(level.bottle.length).toBeGreaterThan(0);
  expect(level.dumbbell).toEqual([]);
});

test('five stand still in a row; six or more walk through in a loop', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await stub(page, 200, squad(5));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(5);
  const lefts = () =>
    page.locator('.lineup svg').evaluateAll((all) => all.map((s) => s.getBoundingClientRect().x));
  const row = await lefts();
  await page.waitForTimeout(300);
  expect(await lefts()).toStrictEqual(row);
  // Figure against figure, centred, all on screen.
  for (const x of row) expect(x).toBeGreaterThanOrEqual(0);

  await page.unroute(`${API}*`);
  await stub(page, 200, squad(8));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(8);
  const before = await lefts();
  await page.waitForTimeout(300);
  const after = await lefts();
  // Everyone walks left at the same pace.
  after.forEach((x, i) => expect(x).toBeLessThan(before[i]));
});

test('with reduced motion the queue stands still', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await stub(page, 200, squad(8));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(8);
  const frame = () => page.locator('.lineup').innerHTML();
  const before = await frame();
  await page.waitForTimeout(400);
  expect(await frame()).toBe(before);
});

for (const [width, height] of [
  [320, 568],
  [390, 844],
  [820, 1180],
  [1280, 600],
  [1440, 900],
]) {
  test(`at ${width}×${height} fits the width and keeps the hero clear of the squad`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height });
    await stub(page, 200, squad(5, { name: '周末网球和早起跑步俱乐部' }));
    await page.goto('/join/K7M2QX9P?lang=zh-Hans');
    await expect(page.locator('.lineup svg')).toHaveCount(5);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(width);
    const hero = await Promise.all(
      ['#eyebrow', '#name', '#sub', '#get', '#code', '.wc-lang'].map((s) =>
        page.locator(s).boundingBox(),
      ),
    );
    const figures = await Promise.all(
      (await page.locator('.lineup svg').all()).map((s) => s.boundingBox()),
    );
    const footer = await page.locator('footer').boundingBox();
    for (const box of [...hero, ...figures]) {
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(width);
    }
    for (const text of hero) for (const f of figures) expect(overlaps(text, f)).toBe(false);
    const logo = await page.locator('.wc-logo').boundingBox();
    expect(logo.x + logo.width).toBeLessThan(hero[5].x);
    for (const f of figures) expect(f.y + f.height).toBeLessThanOrEqual(footer.y);
    // The button and the code are tap targets.
    expect(hero[3].height).toBeGreaterThanOrEqual(44);
    expect(hero[4].height).toBeGreaterThanOrEqual(44);
  });
}

test('the home page’s button opens the App Store, with Apple’s logo', async ({ page }) => {
  for (const path of ['/', '/zh/', '/zh-hant/']) {
    await page.goto(path);
    await expect(page.locator('.btn')).toHaveAttribute('href', APP_STORE);
    await expect(page.locator('.btn svg')).toBeVisible();
  }
});
