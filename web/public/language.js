// The site speaks Simplified Chinese unless the visitor picks another language. A tap on a
// language link (简体 / 繁體 / EN, on any page) is remembered on this browser, so the home page at
// / sends someone who picked English to /en/ (or 繁體 to /zh-hant/) before it draws, and the
// invite page opens in their language. Loaded as a plain script at the top of each page.
(() => {
  const KEY = 'wildcard.language';
  const HOME = { 'zh-Hans': '/', 'zh-Hant': '/zh-hant/', en: '/en/' };
  let picked = null;
  try {
    picked = localStorage.getItem(KEY);
  } catch {
    // Storage blocked (a private window, cookies off): every visit starts in Simplified Chinese.
  }
  if (!(picked in HOME)) picked = null;
  window.WildcardLanguage = { picked };
  if (location.pathname === '/' && picked && picked !== 'zh-Hans') {
    location.replace(HOME[picked] + location.search + location.hash);
  }
  document.addEventListener('click', (event) => {
    const link = event.target instanceof Element && event.target.closest('nav a[hreflang]');
    if (!link || !(link.hreflang in HOME)) return;
    try {
      localStorage.setItem(KEY, link.hreflang);
    } catch {
      // Not remembered; the link still opens that language.
    }
  });
})();
