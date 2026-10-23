import { expect, test } from '@playwright/test';

const pages = [
  { path: '/', slogan: 'Become everyday athletes', button: 'Get your wildcard', legal: '/' },
  { path: '/zh/', slogan: '人人都是运动员', button: '领取外卡', legal: '/zh/' },
  { path: '/zh-hant/', slogan: '人人都是運動員', button: '領取外卡', legal: '/zh-hant/' },
];
const sizes = [
  [320, 568],
  [390, 844],
  [820, 1180],
  [1100, 800],
  [1440, 900],
];

const overlaps = (a, b) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

for (const { path, slogan, button, legal } of pages) {
  test(`${path} says the slogan, offers the button and links its own legal pages`, async ({
    page,
  }) => {
    await page.goto(path);
    await expect(page.locator('.sub')).toHaveText(slogan);
    await expect(page.locator('.btn')).toHaveText(button);
    await expect(page.locator('footer a').nth(0)).toHaveAttribute('href', `${legal}privacy`);
    await expect(page.locator('footer a').nth(1)).toHaveAttribute('href', `${legal}terms`);
    await expect(page.locator('.wc-lang [aria-current="page"]')).toHaveAttribute('href', path);
    // Each language link is at least Apple's 44pt tap target.
    for (const link of await page.locator('.wc-lang a').all())
      expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(44);
  });

  for (const [width, height] of sizes) {
    test(`${path} at ${width}×${height} fits the width and keeps the hero clear of the squad`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height });
      await page.goto(path);
      await expect(page.locator('.btn')).toHaveCSS('opacity', '1');
      const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
      expect(scrollWidth).toBe(width);

      const hero = await Promise.all(
        ['#word', '.sub', '.btn', '.wc-lang'].map((s) => page.locator(s).boundingBox()),
      );
      const squad = await Promise.all((await page.locator('.c').all()).map((c) => c.boundingBox()));
      expect(squad).toHaveLength(5);
      for (const box of [...hero, ...squad]) {
        expect(box.x).toBeGreaterThanOrEqual(0);
        expect(box.x + box.width).toBeLessThanOrEqual(width);
      }
      for (const text of hero) for (const c of squad) expect(overlaps(text, c)).toBe(false);

      // Feet on the floor: no character reaches into the white footer.
      const footer = await page.locator('footer').boundingBox();
      for (const c of squad) expect(c.y + c.height).toBeLessThanOrEqual(footer.y + 4);
    });
  }
}

test('a tap makes a character say its lines in turn, one bubble at a time, on screen', async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  const kai = page.getByRole('button', { name: 'Kai' });
  const oreo = page.getByRole('button', { name: 'Oreo' });

  await kai.press('Enter');
  await expect(kai.locator('.bubble')).toHaveText("Squad's one short. Get in here!");
  await kai.press('Enter');
  await expect(kai.locator('.bubble')).toHaveText('No couch rot tonight. We lift.');

  await oreo.dispatchEvent('pointerdown');
  await expect(oreo.locator('.bubble')).toHaveText('The podium is literally empty without you.');
  await expect(page.locator('.bubble.on')).toHaveCount(1);
  await expect(oreo.locator('.bubble')).toHaveCSS('opacity', '1');
  const bubble = await oreo.locator('.bubble').boundingBox();
  expect(bubble.x).toBeGreaterThanOrEqual(0);
  expect(bubble.x + bubble.width).toBeLessThanOrEqual(320);
});

test('the zh-Hant page speaks Traditional Chinese when tapped', async ({ page }) => {
  await page.goto('/zh-hant/');
  const kai = page.getByRole('button', { name: '阿凱' });
  await kai.press('Enter');
  await expect(kai.locator('.bubble')).toHaveText('就差你了，來！');
});

test('the headline runs in with the tape, which is gone once it settles', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body > canvas')).toHaveCount(1);
  await expect(page.locator('.btn')).toHaveCSS('opacity', '1');
  await expect(page.locator('body > canvas')).toHaveCount(0);
});

test('with reduced motion there is no tape and the squad stands still', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/zh/');
  await expect(page.locator('.btn')).toHaveCSS('opacity', '1');
  await expect(page.locator('#word')).toHaveCSS('opacity', '1');
  await expect(page.locator('body > canvas')).toHaveCount(0);
  const frame = () => page.locator('.c g').first().innerHTML();
  const before = await frame();
  await page.waitForTimeout(500);
  expect(await frame()).toBe(before);
});

test('the legal pages keep their URLs', async ({ request }) => {
  for (const lang of ['', 'zh/', 'zh-hant/'])
    for (const doc of ['privacy', 'terms'])
      expect((await request.get(`/${lang}${doc}`)).status()).toBe(200);
});
