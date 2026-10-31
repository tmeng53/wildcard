// The invite page: looks the code in the link up (GET /public/squad-invites/{code}, no sign-in) and
// shows the squad's name and size over its members' own characters in the 排队入场 queue, each
// playing its persona's idle. The button opens the App Store; the code is there for anyone who
// already has the app. The language follows ?lang=, else the browser's.
import { dress, leveled } from '/character/dress.js';
import { lineup } from '/character/lineup.js';

const API = 'https://api.wildcardsquad.com';
const APP_STORE = 'https://apps.apple.com/app/id6826015677';
const C = window.WILDCARD_CHARACTERS;
const A = window.WildcardAvatar;

const WORDS = {
  'zh-Hans': {
    language: '语言',
    home: '/zh/',
    legal: '/zh/',
    privacy: '隐私政策',
    terms: '使用条款',
    title: (name) => `加入「${name}」· 外卡`,
    invited: '你被邀请加入',
    members: (n) => `${n} 名队员，就差你了`,
    full: '这个小队已经满员了',
    join: '加入小队',
    get: '领取外卡',
    code: '已经装了外卡？邀请码',
    copied: '已复制',
    unknown: ['这个邀请码不对', '找发链接的朋友再要一个吧'],
    busy: ['打开太多次了', '歇一会儿再刷新试试'],
    offline: ['暂时连不上', '检查一下网络，再刷新试试'],
  },
  'zh-Hant': {
    language: '語言',
    home: '/zh-hant/',
    legal: '/zh-hant/',
    privacy: '隱私權政策',
    terms: '使用條款',
    title: (name) => `加入「${name}」· 外卡`,
    invited: '你被邀請加入',
    members: (n) => `${n} 名隊員，就差你了`,
    full: '這個小隊已經滿員了',
    join: '加入小隊',
    get: '領取外卡',
    code: '已經裝了外卡？邀請碼',
    copied: '已複製',
    unknown: ['這個邀請碼不對', '找傳連結的朋友再要一個吧'],
    busy: ['打開太多次了', '歇一會兒再重新整理試試'],
    offline: ['暫時連不上', '檢查一下網路，再重新整理試試'],
  },
  en: {
    language: 'Language',
    home: '/',
    legal: '/',
    privacy: 'Privacy',
    terms: 'Terms',
    title: (name) => `Join ${name} · Wildcard`,
    invited: "You're invited to join",
    members: (n) => `${n} in. You're next.`,
    full: "This squad's full.",
    join: 'Join the squad',
    get: 'Get your wildcard',
    code: 'Got the app? Invite code',
    copied: 'Copied',
    unknown: ["This invite code doesn't work", 'Ask your friend for a fresh link.'],
    busy: ['Too many tries', 'Take a breather, then refresh.'],
    offline: ["Can't reach us right now", 'Check your connection, then refresh.'],
  },
};

function language() {
  const asked = new URLSearchParams(location.search).get('lang');
  if (asked in WORDS) return asked;
  for (const tag of navigator.languages ?? [navigator.language]) {
    const t = tag.toLowerCase();
    if (!t.startsWith('zh')) continue;
    return /hant|tw|hk|mo/.test(t) ? 'zh-Hant' : 'zh-Hans';
  }
  return 'en';
}

const lang = language();
const words = WORDS[lang];
const $ = (id) => document.getElementById(id);

// The page's own words in this language.
document.documentElement.lang = lang;
document.querySelector('[data-words="language"]').setAttribute('aria-label', words.language);
document.querySelector('[data-home]').href = words.home;
for (const link of document.querySelectorAll('.wc-lang a')) {
  const url = new URL(location.href);
  url.searchParams.set('lang', link.dataset.lang);
  link.href = url.pathname + url.search;
  if (link.dataset.lang === lang) link.setAttribute('aria-current', 'page');
}
$('privacy').textContent = words.privacy;
$('privacy').href = `${words.legal}privacy`;
$('terms').textContent = words.terms;
$('terms').href = `${words.legal}terms`;
$('get').href = APP_STORE;

// The code is the path's last part (/join/K7M2QX9P), or ?code=.
const code = (
  location.pathname.split('/').filter(Boolean)[1] ??
  new URLSearchParams(location.search).get('code') ??
  ''
).trim();

function show({ eyebrow = '', name, sub, button, withCode = false }) {
  $('eyebrow').textContent = eyebrow;
  $('eyebrow').hidden = eyebrow === '';
  $('name').textContent = name;
  $('sub').textContent = sub;
  $('get-words').textContent = button;
  $('code').hidden = !withCode;
  if (withCode) {
    $('code-label').textContent = words.code;
    $('code-value').textContent = code.toUpperCase();
  }
  $('hero').hidden = false;
}

async function lookUp() {
  if (code === '') return { problem: 'unknown' };
  try {
    const response = await fetch(`${API}/public/squad-invites/${encodeURIComponent(code)}`);
    if (response.ok) return { squad: await response.json() };
    if (response.status === 404) return { problem: 'unknown' };
    if (response.status === 429) return { problem: 'busy' };
    return { problem: 'offline' };
  } catch {
    return { problem: 'offline' };
  }
}

// Copies the code; the label says so for a moment.
let copiedTimer = 0;
$('code').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(code.toUpperCase());
  } catch {
    return;
  }
  $('code-label').textContent = words.copied;
  clearTimeout(copiedTimer);
  copiedTimer = setTimeout(() => ($('code-label').textContent = words.code), 1600);
});

// 排队入场: each member who has made a character, earliest first, playing its persona's idle.
function play(looks) {
  const strip = $('lineup');
  const members = looks
    .filter((look) => C.variants.body.includes(look.variants?.body))
    .map((look) => ({
      art: dress(C, look.variants, look.colors ?? {}),
      level: leveled(C, look.variants),
      idle: C.idle[C.personas.includes(look.persona) ? look.persona : 'deadpan'],
    }));
  const figures = members.map(() => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 240 320');
    svg.appendChild(document.createElementNS('http://www.w3.org/2000/svg', 'g'));
    strip.appendChild(svg);
    return svg;
  });
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const t0 = performance.now();
  // The strip's size, read when it changes rather than every frame.
  let row = lineup(members.length, strip.clientWidth, strip.clientHeight);
  const frame = () => {
    const t = (performance.now() - t0) / 1000;
    const spots = reduce ? row.rest() : row.spots(t);
    members.forEach((member, i) => {
      const { left, lift } = spots[i];
      figures[i].style.transform = `translate(${left.toFixed(1)}px, ${(-lift).toFixed(1)}px)`;
      figures[i].firstChild.innerHTML = A.figure(member, A.pose(member.idle, reduce ? 0 : t));
    });
    if (!reduce) requestAnimationFrame(frame);
  };
  new ResizeObserver(() => {
    row = lineup(members.length, strip.clientWidth, strip.clientHeight);
    if (reduce) frame();
  }).observe(strip);
  frame();
}

const { squad, problem } = await lookUp();
if (squad) {
  document.title = words.title(squad.name);
  show({
    eyebrow: words.invited,
    name: squad.name,
    sub: squad.full ? words.full : words.members(squad.memberCount),
    button: squad.full ? words.get : words.join,
    withCode: !squad.full,
  });
  play(squad.looks);
} else {
  const [name, sub] = words[problem];
  show({ name, sub, button: words.get });
}
