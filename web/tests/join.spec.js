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

// Long enough for the ticket to be dealt and checked, five to walk in and the hero to rise in.
const SETTLE = 3900;

const overlaps = (a, b) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

test('shows the squad, its size and the code, and the button opens the App Store', async ({
  page,
}) => {
  const asked = await stub(page, 200, squad(3));
  await page.goto('/join/k7m2qx9p?lang=zh-Hans');
  await expect(page.locator('#name')).toHaveText('周末网球');
  await expect(page.locator('#eyebrow')).toHaveText('你收到一张外卡');
  await expect(page.locator('#sub')).toHaveText('3 人已上场，就等你了');
  await expect(page.locator('#get')).toHaveText('领取外卡');
  await expect(page.locator('#copy')).toHaveText('复制');
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
  await expect(page.locator('#sub')).toHaveText('2 人已上場，就等你了');
  await expect(page.locator('#privacy')).toHaveAttribute('href', '/zh-hant/privacy');
  await expect(page.locator('.wc-lang [aria-current="page"]')).toHaveText('繁體');
  await page.locator('.wc-lang a[lang="en"]').click();
  await expect(page).toHaveURL(/\/join\/K7M2QX9P\?lang=en$/);
  await expect(page.locator('#sub')).toHaveText('2 in. Waiting on you.');
  await expect(page.locator('#get')).toHaveText('Get your wildcard');
  await expect(page.locator('#terms')).toHaveAttribute('href', '/terms');
});

test('opens in Simplified Chinese whatever the browser speaks', async ({ browser }) => {
  for (const locale of ['en-US', 'zh-TW']) {
    const context = await browser.newContext({ locale });
    const page = await context.newPage();
    await stub(page, 200, squad(2));
    await page.goto('/join/K7M2QX9P');
    await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
    await expect(page.locator('#sub')).toHaveText('2 人已上场，就等你了');
    await expect(page.locator('.wc-logo')).toHaveAttribute('href', '/');
    await context.close();
  }
});

test('opens in the language last picked on the site', async ({ page }) => {
  await page.goto('/');
  await page.locator('.wc-lang a[lang="en"]').click();
  await expect(page).toHaveURL(/\/en\/$/);
  await stub(page, 200, squad(2));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('#sub')).toHaveText('2 in. Waiting on you.');
  await expect(page.locator('.wc-logo')).toHaveAttribute('href', '/en/');
});

test('deals the ticket, tears its stub off, then the squad walks on', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await stub(page, 200, squad(4));
  await page.goto('/join/K7M2QX9P?lang=zh-Hans');
  await expect(page.locator('#ticket')).toHaveClass(/checked/);
  await expect(page.locator('#stub-words')).toHaveText('入场券');
  await expect(page.locator('#stamp')).toHaveText(/^\d{4}\.\d{2}\.\d{2}$/);
  // While the ticket is checked, the squad waits past the right edge and the button isn't up yet.
  const xs = () =>
    page.locator('.lineup svg').evaluateAll((all) => all.map((s) => s.getBoundingClientRect().x));
  for (const x of await xs()) expect(x).toBeGreaterThan(390);
  // Dealt (in 0.6 s), with the stub still on.
  await page.waitForTimeout(700);
  const ticket = await page.locator('.face').boundingBox();
  await page.waitForTimeout(SETTLE);
  // The stub is gone, the ticket didn't move, and everyone is on the floor.
  expect(await page.locator('#stub').evaluate((s) => getComputedStyle(s).opacity)).toBe('0');
  expect(await page.locator('.face').boundingBox()).toStrictEqual(ticket);
  for (const x of await xs()) expect(x).toBeLessThan(390);
  expect(await page.locator('#get').evaluate((s) => getComputedStyle(s).opacity)).toBe('1');
});

test('with reduced motion the ticket shows already checked', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await stub(page, 200, squad(3));
  await page.goto('/join/K7M2QX9P?lang=en');
  await expect(page.locator('#name')).toHaveText('周末网球');
  await expect(page.locator('#stub')).toBeHidden();
  await expect(page.locator('#get')).toBeVisible();
});

test('a full squad says so and offers the app without the code', async ({ page }) => {
  await stub(page, 200, squad(8, { full: true }));
  await page.goto('/join/K7M2QX9P?lang=en');
  await expect(page.locator('#sub')).toHaveText("This squad's full.");
  await expect(page.locator('#get')).toHaveText('Get your wildcard');
  await expect(page.locator('#code')).toBeHidden();
  // Its ticket is dealt but never checked: the stub stays on.
  await expect(page.locator('#ticket')).not.toHaveClass(/checked/);
  await page.waitForTimeout(SETTLE);
  await expect(page.locator('#stub-words')).toHaveText('ADMIT ONE');
  await expect(page.locator('#stub')).toBeVisible();
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
    // No squad, no ticket: the words alone, as wide as the page lets them be.
    await expect(page.locator('#ticket')).toHaveClass(/plain/);
    await expect(page.locator('#stub')).toBeHidden();
    await page.setViewportSize({ width: 1280, height: 800 });
    const { height } = await page.locator('#name').boundingBox();
    const line = await page
      .locator('#name')
      .evaluate((h) => parseFloat(getComputedStyle(h).lineHeight));
    expect(Math.round(height / line)).toBe(1);
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

test('an arm bends at the elbow whatever path commands its art is drawn with', async ({ page }) => {
  await stub(page, 200, squad(1));
  await page.goto('/join/K7M2QX9P');
  // POWDER DAY's sleeves are drawn with relative commands (l, h, v, c); a bent arm used to read
  // them as absolute points and shoot a streak of the top's colour across the page.
  const boxes = await page.evaluate(async () => {
    const { dress } = await import('/character/dress.js');
    const C = window.WILDCARD_CHARACTERS;
    const armR = C.parts.findIndex(({ id }) => id === 'armR');
    const box = (top, bend) => {
      const art = dress(C, { body: 'bichon', top, prop: 'dumbbell' });
      const poses = window.WildcardAvatar.pose({ loops: true, duration: 1, tracks: [] }, 0);
      poses[armR].bend = bend;
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.innerHTML = window.WildcardAvatar.figure({ art, level: [] }, poses);
      document.body.append(svg);
      const { x, y, width, height } = svg.getBBox();
      svg.remove();
      return [x, y, x + width, y + height].map(Math.round);
    };
    return Object.fromEntries(
      ['powder-salmon', 'warmup-tee'].map((top) => [
        top,
        { rest: box(top, 0), bent: box(top, -35) },
      ]),
    );
  });
  for (const { rest, bent } of Object.values(boxes)) {
    // Bending the forearm moves the hand a little; it never reaches far past the figure.
    bent.forEach((edge, i) => expect(Math.abs(edge - rest[i])).toBeLessThan(30));
  }
});

test('an arm bends as the app bends it, case for case', async ({ page }) => {
  // The app writes these (AvatarDomainTests' ArmBendCasesTests), so the two players can't drift.
  const { arm, cases } = JSON.parse(
    readFileSync(new URL('../../ios/Packages/Avatar/Tests/arm-bend-cases.json', import.meta.url)),
  );
  await stub(page, 200, squad(1));
  await page.goto('/join/K7M2QX9P');
  const drawn = await page.evaluate(
    ({ arm, cases }) => {
      const part = { pivot: arm.shoulder, elbow: { at: arm.elbow, hand: arm.hand } };
      return cases.map(
        ({ d, degrees }) =>
          window.WildcardAvatar.bent(`<path d="${d}"/>`, part, degrees).match(/ d="([^"]*)"/)[1],
      );
    },
    { arm, cases },
  );
  const words = (path) => path.split(' ').map((w) => (/^[A-Z]$/.test(w) ? w : +w));
  cases.forEach(({ about, bent }, i) => {
    const [mine, app] = [words(drawn[i]), words(bent)];
    expect(mine.length, about).toBe(app.length);
    // Each rounds to two decimals on its own, so a hundredth apart is the same point.
    mine.forEach((w, k) =>
      typeof w === 'string'
        ? expect(w, about).toBe(app[k])
        : expect(Math.abs(w - app[k]), about).toBeLessThanOrEqual(0.011),
    );
  });
});

test('five walk in and stand still in a row; six or more walk through in a loop', async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await stub(page, 200, squad(5));
  await page.goto('/join/K7M2QX9P');
  await expect(page.locator('.lineup svg')).toHaveCount(5);
  const lefts = () =>
    page.locator('.lineup svg').evaluateAll((all) => all.map((s) => s.getBoundingClientRect().x));
  // They come in from past the right edge, the last one last.
  const entering = await lefts();
  expect(entering[4]).toBeGreaterThan(390);
  await page.waitForTimeout(SETTLE);
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
    await page.waitForTimeout(SETTLE);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(width);
    const hero = await Promise.all(
      ['#eyebrow', '#name', '#sub', '#get', '#copy', '.wc-lang', '#code'].map((s) =>
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
  for (const path of ['/', '/en/', '/zh-hant/']) {
    await page.goto(path);
    await expect(page.locator('.btn')).toHaveAttribute('href', APP_STORE);
    await expect(page.locator('.btn svg')).toBeVisible();
  }
});

test('the copy button copies the code and says so for a moment', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await stub(page, 200, squad(3));
  await page.goto('/join/k7m2qx9p?lang=zh-Hans');
  await page.waitForTimeout(SETTLE);
  await page.locator('#copy').click();
  await expect(page.locator('#copy')).toHaveText('已复制');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('K7M2QX9P');
  await expect(page.locator('#copy')).toHaveText('复制', { timeout: 3000 });
});

test('in WeChat it points at the menu to open the page in a browser; elsewhere it doesn’t', async ({
  browser,
}) => {
  const wechat = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.50',
  });
  const page = await wechat.newPage();
  await stub(page, 200, squad(2));
  await page.goto('/join/K7M2QX9P?lang=zh-Hans');
  await expect(page.locator('#wechat')).toHaveText('点右上角 ··· 选「在浏览器打开」');
  const tip = await page.locator('#wechat').boundingBox();
  const lang = await page.locator('.wc-lang').boundingBox();
  expect(overlaps(tip, lang)).toBe(false);
  await wechat.close();

  const other = await browser.newPage();
  await stub(other, 200, squad(2));
  await other.goto('/join/K7M2QX9P?lang=zh-Hans');
  await expect(other.locator('#name')).toHaveText('周末网球');
  await expect(other.locator('#wechat')).toBeHidden();
  await other.close();
});

test('the site names the app for invite links, as JSON', async ({ request }) => {
  const response = await request.get('/.well-known/apple-app-site-association');
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toBe('application/json');
  const { applinks } = await response.json();
  expect(applinks.details).toStrictEqual([
    {
      appIDs: ['WFY3YV6SPP.com.wildcardsquad.wildcard'],
      components: [{ '/': '/join/*', comment: expect.any(String) }],
    },
  ]);
});
