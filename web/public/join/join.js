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
    invited: '你收到一张外卡',
    members: (n) => `${n} 人已上场，就等你了`,
    full: '这个小队已经满员了',
    join: '领取外卡',
    get: '领取外卡',
    code: '邀请码',
    copy: '复制',
    copied: '已复制',
    wechat: '点右上角 ··· 选「在浏览器打开」',
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
    invited: '你收到一張外卡',
    members: (n) => `${n} 人已上場，就等你了`,
    full: '這個小隊已經滿員了',
    join: '領取外卡',
    get: '領取外卡',
    code: '邀請碼',
    copy: '複製',
    copied: '已複製',
    wechat: '點右上角 ··· 選「在瀏覽器開啟」',
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
    invited: 'You got a wildcard',
    members: (n) => `${n} in. Waiting on you.`,
    full: "This squad's full.",
    join: 'Get your wildcard',
    get: 'Get your wildcard',
    code: 'Invite code',
    copy: 'Copy',
    copied: 'Copied',
    wechat: 'Tap ··· at the top right, then Open in Browser',
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
    $('copy-words').textContent = words.copy;
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

// Copies the code; the button says so for a moment, and the squad cheers.
let copiedTimer = 0;
$('copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(code.toUpperCase());
  } catch {
    return;
  }
  $('copy-words').textContent = words.copied;
  $('copy').classList.add('done');
  cheerAll();
  clearTimeout(copiedTimer);
  copiedTimer = setTimeout(() => {
    $('copy-words').textContent = words.copy;
    $('copy').classList.remove('done');
  }, 1600);
});

// 排队入场: each member who has made a character, earliest first. They walk in from the right one
// after another with small hops, wave, then idle in their persona; every few seconds one of them
// waves again. A tap on a figure
// makes it cheer, and copying the code makes the whole row cheer, left to right.
const ENTER = { delay: 0.35, stagger: 0.16, walk: 0.95 };
// How long a move takes to blend in from idle and back.
const FADE = 0.18;
let cheerAll = () => {};

function play(looks) {
  const strip = $('lineup');
  const members = looks
    .filter((look) => C.variants.body.includes(look.variants?.body))
    .map((look) => {
      const persona = C.personas.includes(look.persona) ? look.persona : 'deadpan';
      return {
        art: dress(C, look.variants, look.colors ?? {}),
        level: leveled(C, look.variants),
        idle: C.idle[persona],
        cheer: C.cheer[persona],
      };
    });
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const count = members.length;
  const actors = members.map((member, i) => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 240 320');
    svg.appendChild(document.createElementNS('http://www.w3.org/2000/svg', 'g'));
    strip.appendChild(svg);
    const actor = { member, svg, move: null, start: 0, arrive: ENTER.delay + i * ENTER.stagger };
    // Redrawn every frame, so react on the press, not the click.
    svg.addEventListener('pointerdown', () => cheer(actor, now()));
    return actor;
  });
  const t0 = performance.now();
  const now = () => (performance.now() - t0) / 1000;
  const cheer = (actor, t) => {
    if (reduce) return;
    actor.move = actor.member.cheer;
    actor.start = t;
  };
  const wave = (actor, t) => {
    actor.move = C.moves.wave;
    actor.start = t;
  };
  cheerAll = () => actors.forEach((actor, i) => cheer(actor, now() + i * 0.08));

  // The strip's size, read when it changes rather than every frame.
  let row = lineup(count, strip.clientWidth, strip.clientHeight);
  let nextWave = ENTER.delay + count * ENTER.stagger + ENTER.walk + 3;
  const ease = (f) => 1 - (1 - f) ** 3;
  const frame = () => {
    const t = reduce ? 0 : now();
    const spots = reduce ? row.rest() : row.spots(t);
    actors.forEach((actor, i) => {
      let { left, lift } = spots[i];
      if (!reduce && !row.walks) {
        // Walking in: from past the right edge to the row, hopping, slowing into place.
        const f = Math.min(1, Math.max(0, (t - actor.arrive) / ENTER.walk));
        const from = strip.clientWidth + row.figureWidth * 0.2;
        left = from + (left - from) * ease(f);
        lift = f < 1 ? Math.abs(Math.sin(f * Math.PI * 3)) * row.figureWidth * 0.08 : 0;
        // Arrived: a wave hello.
        if (f >= 1 && actor.arrived === undefined) {
          actor.arrived = true;
          wave(actor, t + 0.1);
        }
      }
      actor.svg.style.transform = `translate(${left.toFixed(1)}px, ${(-lift).toFixed(1)}px)`;
      // A move plays, then blends back to idle over FADE before it's dropped.
      const end = actor.move ? actor.start + actor.move.duration + FADE : 0;
      const busy = actor.move && t >= actor.start && t < end;
      if (actor.move && t >= end) actor.move = null;
      const poses = busy
        ? A.perform(actor.member.idle, actor.move, actor.start, t, FADE)
        : A.pose(actor.member.idle, t);
      actor.svg.firstChild.innerHTML = A.figure(actor.member, poses);
    });
    // Now and then someone waves again.
    if (!reduce && t >= nextWave && actors.length > 0) {
      const actor = actors[Math.floor(Math.random() * actors.length)];
      if (!actor.move) wave(actor, t);
      nextWave = t + 3 + Math.random() * 2;
    }
    if (!reduce) requestAnimationFrame(frame);
  };
  new ResizeObserver(() => {
    row = lineup(count, strip.clientWidth, strip.clientHeight);
    if (reduce) frame();
  }).observe(strip);
  frame();
}

// WeChat's browser won't open the app or the App Store: point at its menu.
if (/MicroMessenger/i.test(navigator.userAgent)) {
  $('wechat').textContent = words.wechat;
  $('wechat').hidden = false;
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
