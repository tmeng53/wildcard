// The app's character player (ios/Packages/Avatar, AvatarDomain), ported to the browser: pose a clip
// at a time, blend idle into a one-shot move and back, lay out the rig and draw each part as SVG.
(() => {
  const C = window.WILDCARD_CHARACTERS;
  const PARTS = C.parts;
  const INDEX = Object.fromEntries(PARTS.map((p, i) => [p.id, i]));
  const NAMED = {
    easeIn: [0.42, 0, 1, 1],
    easeOut: [0, 0, 0.58, 1],
    easeInOut: [0.42, 0, 0.58, 1],
    backOut: [0.34, 1.56, 0.64, 1],
  };
  const CHANNELS = ['rotation', 'x', 'y', 'scaleX', 'scaleY', 'opacity'];

  function bezier([x1, y1, x2, y2], f) {
    if (f <= 0) return 0;
    if (f >= 1) return 1;
    const curve = (t, a, b) => ((1 + 3 * a - 3 * b) * t + (3 * b - 6 * a)) * t * t + 3 * a * t;
    let lo = 0;
    let hi = 1;
    let t = f;
    for (let i = 0; i < 40; i++) {
      const v = curve(t, x1, x2);
      if (Math.abs(v - f) < 1e-6) break;
      if (v < f) lo = t;
      else hi = t;
      t = (lo + hi) / 2;
    }
    return curve(t, y1, y2);
  }

  function ease(e, f) {
    if (!e || e === 'linear') return f;
    if (e === 'hold') return f >= 1 ? 1 : 0;
    return bezier(typeof e === 'string' ? NAMED[e] : e, f);
  }

  function value(keys, t) {
    if (t <= keys[0].t) return keys[0].v;
    const last = keys[keys.length - 1];
    if (t >= last.t) return last.v;
    for (let i = 0; i < keys.length - 1; i++) {
      const a = keys[i];
      const b = keys[i + 1];
      if (t < b.t) return a.v + (b.v - a.v) * ease(b.ease, (t - a.t) / (b.t - a.t));
    }
    return last.v;
  }

  const rest = () =>
    PARTS.map((p) => ({ rotation: 0, x: 0, y: 0, scaleX: 1, scaleY: 1, opacity: p.opacity }));

  function pose(clip, time) {
    const t = clip.loops
      ? ((time % clip.duration) + clip.duration) % clip.duration
      : Math.max(0, Math.min(clip.duration, time));
    const poses = rest();
    for (const track of clip.tracks)
      if (track.part in INDEX) poses[INDEX[track.part]][track.channel] = value(track.keys, t);
    return poses;
  }

  const blend = (a, b, f) =>
    a.map((x, i) => {
      const out = {};
      for (const c of CHANNELS) out[c] = x[c] + (b[i][c] - x[c]) * f;
      return out;
    });
  const smooth = (f) => f * f * (3 - 2 * f);

  // Idle, crossfading into a one-shot move at `start` and back to idle when it ends (Performance).
  function perform(idle, move, start, t, fade) {
    if (!move || t < start) return pose(idle, t);
    const end = start + move.duration;
    if (t >= end) {
      const e = t - end;
      const target = pose(idle, t);
      return e < fade ? blend(pose(move, move.duration), target, smooth(e / fade)) : target;
    }
    const e = t - start;
    const target = pose(move, e);
    return e < fade ? blend(pose(idle, start), target, smooth(e / fade)) : target;
  }

  const multiply = ([a, b, c, d, e, f], [A, B, C2, D, E, F]) => [
    a * A + c * B,
    b * A + d * B,
    a * C2 + c * D,
    b * C2 + d * D,
    a * E + c * F + e,
    b * E + d * F + f,
  ];

  function layout(poses) {
    const matrices = new Array(PARTS.length);
    const opacities = new Array(PARTS.length);
    const place = (i) => {
      if (matrices[i]) return;
      const part = PARTS[i];
      const q = poses[i];
      const [px, py] = part.pivot;
      const r = (q.rotation * Math.PI) / 180;
      let m = [1, 0, 0, 1, -px, -py];
      m = multiply([q.scaleX, 0, 0, q.scaleY, 0, 0], m);
      m = multiply([Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0], m);
      m = multiply([1, 0, 0, 1, px + q.x, py + q.y], m);
      if (part.parent) {
        const j = INDEX[part.parent];
        place(j);
        matrices[i] = multiply(matrices[j], m);
        opacities[i] = q.opacity * opacities[j];
      } else {
        matrices[i] = m;
        opacities[i] = q.opacity;
      }
    };
    PARTS.forEach((_, i) => place(i));
    return { matrices, opacities };
  }

  const format = (m) => m.map((x) => x.toFixed(3)).join(' ');

  // A prop that keeps level turns back by everything that carries it, as the app's Figure does.
  function leveled(poses, level) {
    if (!level?.length) return poses;
    const out = poses.map((q) => ({ ...q }));
    for (const i of level) {
      let turned = 0;
      for (let p = PARTS[i].parent; p; p = PARTS[INDEX[p]].parent) turned += out[INDEX[p]].rotation;
      out[i].rotation = -turned;
    }
    return out;
  }

  // SVG markup of one cast member in a pose.
  function figure(member, poses) {
    const { matrices, opacities } = layout(leveled(poses, member.level));
    let svg = '';
    PARTS.forEach((part, i) => {
      const art = member.art[i];
      if (art && opacities[i] > 0)
        svg += `<g transform="matrix(${format(matrices[i])})" opacity="${opacities[i].toFixed(3)}">${art}</g>`;
    });
    return svg;
  }

  window.WildcardAvatar = { pose, perform, figure };
})();
