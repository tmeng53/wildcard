// The home page's squad: a warm-up class in sync, a tap makes one cheer and invite you in.
// Then the headline runs in (冲线) and the rest of the hero fades in as it settles.
(() => {
  const C = window.WILDCARD_CHARACTERS;
  const A = window.WildcardAvatar;
  // Which column of LINES and which name to use: Simplified, Traditional, English.
  const lang = document.documentElement.lang;
  const column = lang === 'zh-Hans' ? 0 : lang === 'zh-Hant' ? 1 : 2;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const t0 = performance.now();
  const now = () => (performance.now() - t0) / 1000;

  // What each one says when tapped: an invitation, in their own persona, in zh-Hans, zh-Hant and en.
  // The English is written for English speakers, not translated.
  // Each tap shows the next line.
  const LINES = {
    kai: [
      ['就差你了，来！', '就差你了，來！', "Squad's one short. Get in here!"],
      ['下班别瘫着，来练', '下班別癱著，來練', 'No couch rot tonight. We lift.'],
      ['把群里那几个也拉上', '把群裡那幾個也拉上', "Leg day's better with the group chat."],
    ],
    snow: [
      ['你…要不要一起？', '你…要不要一起？', 'Um… wanna be gym buddies?'],
      ['有我在，不尴尬', '有我在，不尷尬', "Gym anxiety? Same. Let's go together."],
      ['我先打卡，你跟上', '我先打卡，你跟上', 'I logged my workout. Your turn?'],
    ],
    garfield: [
      [
        '不想练？写张请假条也算',
        '不想練？寫張請假條也算',
        'Skipping? File an excuse. Still counts.',
      ],
      ['你来，我就动一下', '你來，我就動一下', "You show up, I'll do one rep. Maybe."],
      ['坦白放纵餐也算打卡', '坦白放縱餐也算打卡', 'Ate the whole pizza? Confess. It counts.'],
    ],
    buns: [
      ['外卡给你留着呢', '外卡給你留著呢', "There's a wildcard with your name on it."],
      ['组个队，一起上场', '組個隊，一起上場', 'Squad up. Gains hit different together.'],
      ['周日战报等你上榜', '週日戰報等你上榜', 'Sunday recap drops soon. Be in it.'],
    ],
    oreo: [
      ['颁奖台就缺你了', '頒獎台就缺你了', 'The podium is literally empty without you.'],
      ['你不来，我哭给你看', '你不來，我哭給你看', "Ghost us and I'm crying. Publicly."],
      ['人人都是运动员，包括你', '人人都是運動員，包括你', 'Main character energy. Yes, you.'],
    ],
  };

  // The class, the same for everyone: [move, pause after]; each starts a beat after the one on its left.
  const CLASS = [
    ['warmup', 0.5],
    ['warmup', 0.8],
    ['stretch', 0.8],
    ['pump', 0.4],
    ['pump', 0.8],
    ['wave', 1.6],
  ];
  const START = [0.5, 0.58, 0.66, 0.74, 0.82];
  // Everyone on the site holds a dumbbell, whatever prop their look carries.
  const SWAP = { propR: C.dumbbell };

  const squad = document.getElementById('squad');
  const site = document.querySelector('.site');
  const actors = C.cast.map((member, i) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'c';
    button.setAttribute('aria-label', [member.zh, member.zhHant, member.en][column]);
    button.innerHTML =
      '<svg viewBox="0 0 240 320" aria-hidden="true"><g></g></svg><span class="bubble" aria-live="polite"></span>';
    squad.appendChild(button);
    const actor = {
      member,
      i,
      g: button.querySelector('g'),
      bubble: button.querySelector('.bubble'),
      step: -1,
      move: null,
      start: 0,
      until: START[i],
      line: -1,
      timer: 0,
    };
    // The figure is redrawn every frame, so the shape a finger lands on is gone before 'click'
    // fires; react on the press instead, and keep 'click' for the keyboard (detail 0).
    const tap = () => {
      if (!reduce) play(actor, C.cheer[member.persona], now(), 0.6);
      say(actor);
    };
    button.addEventListener('pointerdown', tap);
    button.addEventListener('click', (e) => {
      if (e.detail === 0) tap();
    });
    return actor;
  });

  function play(actor, move, at, pause) {
    actor.move = move;
    actor.start = at;
    actor.until = at + move.duration + pause;
  }

  function next(actor, t) {
    actor.step = (actor.step + 1) % CLASS.length;
    const [move, pause] = CLASS[actor.step];
    play(actor, C.moves[move], Math.max(t, actor.until), pause);
  }

  function say(actor) {
    // One speaker at a time, so bubbles never stack on a small screen.
    for (const other of actors) if (other !== actor) other.bubble.classList.remove('on');
    const lines = LINES[actor.member.id];
    actor.line = (actor.line + 1) % lines.length;
    const bubble = actor.bubble;
    bubble.textContent = lines[actor.line][column];
    bubble.classList.add('on');
    // Keep the bubble on screen: nudge it in from the edges; the tail stays over the character.
    bubble.style.setProperty('--dx', '0px');
    const r = bubble.getBoundingClientRect();
    const box = site.getBoundingClientRect();
    const margin = 8;
    const dx = Math.max(box.left + margin - r.left, Math.min(0, box.right - margin - r.right));
    const limit = r.width / 2 - 14;
    bubble.style.setProperty('--dx', `${Math.round(Math.max(-limit, Math.min(limit, dx)))}px`);
    clearTimeout(actor.timer);
    actor.timer = setTimeout(() => bubble.classList.remove('on'), 2400);
  }

  function draw(actor, t) {
    const idle = C.idle[actor.member.persona];
    const poses = actor.move ? A.perform(idle, actor.move, actor.start, t, 0.18) : A.pose(idle, t);
    actor.g.innerHTML = A.figure(actor.member, poses, SWAP);
  }

  if (reduce) {
    // Reduced motion: the squad stands still, at rest; a tap still gets its line.
    for (const actor of actors) draw(actor, 0);
  } else {
    const frame = () => {
      const t = now();
      for (const actor of actors) {
        if (t >= actor.until) next(actor, t);
        draw(actor, t);
      }
      requestAnimationFrame(frame);
    };
    frame();
  }

  // The headline runs in once the wordmark font has loaded; 外卡, the slogan and the button come in
  // as it settles. The wordmark script itself fades the word in under reduced motion.
  const word = document.getElementById('word');
  const rest = [...document.querySelectorAll('[data-settle]')];
  const go = () => {
    for (const el of rest) {
      el.style.opacity = 0;
      el.style.transform = 'translateY(8px)';
    }
    if (!reduce) word.style.opacity = 1;
    const floor = document.querySelector('.floor').getBoundingClientRect();
    window.playWordmarkB(word, {
      tapeColor: getComputedStyle(document.documentElement).getPropertyValue('--brand').trim(),
      floorY: floor.bottom + window.scrollY - 2,
      onSettle: () =>
        rest.forEach((el, i) => {
          const curve = 'cubic-bezier(.2,.7,.3,1)';
          el.style.transition = `opacity .3s ${curve} ${i * 0.08}s, transform .3s ${curve} ${i * 0.08}s`;
          el.style.opacity = 1;
          el.style.transform = '';
        }),
    });
  };
  const start = () => setTimeout(go, 200);
  document.fonts.load('800 60px "Barlow Condensed"').then(start, start);
})();
