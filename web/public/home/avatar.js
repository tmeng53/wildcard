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
  const CHANNELS = ['rotation', 'x', 'y', 'scaleX', 'scaleY', 'opacity', 'bend'];
  // An arm the clip swings without bending trails it a moment behind (Figure's FollowThrough).
  const LAG = 0.09;
  const GIVE = 0.9;
  const MOST = 35;
  const CARRIED = PARTS.map((_, i) =>
    PARTS.flatMap((p, j) => (p.parent === PARTS[i].id ? [j] : [])),
  );

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
    PARTS.map((p) => ({
      rotation: 0,
      x: 0,
      y: 0,
      scaleX: 1,
      scaleY: 1,
      opacity: p.opacity,
      bend: 0,
    }));

  function pose(clip, time) {
    const t = clip.loops
      ? ((time % clip.duration) + clip.duration) % clip.duration
      : Math.max(0, Math.min(clip.duration, time));
    const poses = rest();
    for (const track of clip.tracks)
      if (track.part in INDEX) poses[INDEX[track.part]][track.channel] = value(track.keys, t);
    PARTS.forEach((part, i) => {
      if (!part.elbow) return;
      const mine = clip.tracks.filter((track) => track.part === part.id);
      const swing = mine.find((track) => track.channel === 'rotation');
      if (!swing || mine.some((track) => track.channel === 'bend')) return;
      const back = clip.loops
        ? (((t - LAG) % clip.duration) + clip.duration) % clip.duration
        : Math.max(0, t - LAG);
      // A one-shot straightens over its last moment, so it ends at rest and hands back to idle.
      const settle = clip.loops ? 1 : Math.max(0, Math.min(1, (clip.duration - t) / LAG));
      const trail = GIVE * (value(swing.keys, back) - value(swing.keys, t)) * settle;
      const bend = Math.max(-MOST, Math.min(MOST, trail));
      poses[i].bend = bend;
      for (const j of CARRIED[i]) poses[j].rotation -= bend;
    });
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

  // Turns by `deg` around a point.
  const turn = (deg, [cx, cy]) => {
    const r = (deg * Math.PI) / 180;
    const [c, s] = [Math.cos(r), Math.sin(r)];
    return [c, s, -s, c, cx - c * cx + s * cy, cy - s * cx - c * cy];
  };

  // How much of a part that gives way to an arm shows with the arm turned by `degrees`.
  function gives({ start, end }, degrees) {
    const turned = Math.abs(degrees);
    if (end <= start) return turned < end ? 1 : 0;
    const f = Math.max(0, Math.min(1, (turned - start) / (end - start)));
    return 1 - f * f * (3 - 2 * f);
  }

  function layout(poses) {
    const matrices = new Array(PARTS.length);
    const opacities = new Array(PARTS.length);
    // What each part's children move with: past the elbow for a bent arm.
    const carriers = new Array(PARTS.length);
    const place = (i) => {
      if (matrices[i]) return;
      const part = PARTS[i];
      const q = poses[i];
      // A part that gives way to an arm (a bichon's chin fluff) fades as the arm rises.
      const shown = part.hides ? gives(part.hides, poses[INDEX[part.hides.part]].rotation) : 1;
      const [px, py] = part.pivot;
      const r = (q.rotation * Math.PI) / 180;
      let m = [1, 0, 0, 1, -px, -py];
      m = multiply([q.scaleX, 0, 0, q.scaleY, 0, 0], m);
      m = multiply([Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0], m);
      m = multiply([1, 0, 0, 1, px + q.x, py + q.y], m);
      if (part.parent) {
        const j = INDEX[part.parent];
        place(j);
        matrices[i] = multiply(carriers[j], m);
        opacities[i] = q.opacity * shown * opacities[j];
      } else {
        matrices[i] = m;
        opacities[i] = q.opacity * shown;
      }
      carriers[i] =
        part.elbow && q.bend ? multiply(matrices[i], turn(q.bend, part.elbow.at)) : matrices[i];
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
      for (let p = PARTS[i].parent; p; p = PARTS[INDEX[p]].parent) {
        const q = out[INDEX[p]];
        turned += q.rotation + (PARTS[INDEX[p]].elbow ? q.bend : 0);
      }
      out[i].rotation = -turned;
    }
    return out;
  }

  // An SVG path's `d` as absolute segments (AvatarDomain's PathData): M L H V C S Q T Z, absolute
  // and relative, each as [command, its start point, ...its points] with only M, L, Q, C and Z.
  function segments(d) {
    const tokens = d.match(/[MLHVCSQTZ]|[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi) ?? [];
    const out = [];
    let k = 0;
    let letter = '';
    let pen = [0, 0];
    let start = pen;
    let cubic = null;
    let quad = null;
    const num = () => +tokens[k++];
    while (k < tokens.length) {
      if (/^[a-z]$/i.test(tokens[k])) letter = tokens[k++];
      const relative = letter === letter.toLowerCase();
      const point = () => {
        const [x, y] = [num(), num()];
        return relative ? [pen[0] + x, pen[1] + y] : [x, y];
      };
      const reflect = (c) => (c ? [2 * pen[0] - c[0], 2 * pen[1] - c[1]] : pen);
      const from = pen;
      let [nextCubic, nextQuad] = [null, null];
      switch (letter.toUpperCase()) {
        case 'M':
          pen = start = point();
          out.push(['M', from, pen]);
          letter = relative ? 'l' : 'L';
          break;
        case 'L':
          pen = point();
          out.push(['L', from, pen]);
          break;
        case 'H': {
          const x = num();
          pen = [relative ? pen[0] + x : x, pen[1]];
          out.push(['L', from, pen]);
          break;
        }
        case 'V': {
          const y = num();
          pen = [pen[0], relative ? pen[1] + y : y];
          out.push(['L', from, pen]);
          break;
        }
        case 'C':
        case 'S': {
          const c1 = letter.toUpperCase() === 'C' ? point() : reflect(cubic);
          const c2 = point();
          pen = point();
          out.push(['C', from, c1, c2, pen]);
          nextCubic = c2;
          break;
        }
        case 'Q':
        case 'T': {
          const c = letter.toUpperCase() === 'Q' ? point() : reflect(quad);
          pen = point();
          out.push(['Q', from, c, pen]);
          nextQuad = c;
          break;
        }
        case 'Z':
          out.push(['Z', from]);
          pen = start;
          // Z takes no numbers; a number after it ends the path.
          letter = '';
          break;
        default:
          return out;
      }
      [cubic, quad] = [nextCubic, nextQuad];
    }
    return out;
  }

  // An arm's art bent at the elbow (AvatarDomain's Bend): each point turns around the elbow by
  // more the nearer the hand, and a curve is refitted through its bent middle, so the arm curves.
  function bent(art, part, deg) {
    const [sx, sy] = part.pivot;
    const [ex, ey] = part.elbow.at;
    const [ax, ay] = [part.elbow.hand[0] - sx, part.elbow.hand[1] - sy];
    const length = ax * ax + ay * ay;
    const along = (x, y) => ((x - sx) * ax + (y - sy) * ay) / length;
    const middle = along(ex, ey);
    const move = (x, y) => {
      const f = Math.max(0, Math.min(1, (along(x, y) - middle + 0.15) / 0.4));
      const r = (deg * f * f * (3 - 2 * f) * Math.PI) / 180;
      const [c, s] = [Math.cos(r), Math.sin(r)];
      return [ex + c * (x - ex) - s * (y - ey), ey + s * (x - ex) + c * (y - ey)];
    };
    const n = (v) => +v.toFixed(2);
    const at = ([x, y]) => move(x, y);
    const pt = ([x, y]) => `${n(x)} ${n(y)}`;
    const mix = (points, weights) =>
      [0, 1].map((k) => points.reduce((sum, point, j) => sum + weights[j] * point[k], 0));
    const path = (d) =>
      segments(d)
        .map(([command, from, ...rest]) => {
          if (command === 'Z') return 'Z';
          if (command === 'M' || command === 'L') return `${command} ${pt(at(rest[0]))}`;
          const end = rest[rest.length - 1];
          const [f, t] = [at(from), at(end)];
          if (command === 'Q') {
            // The quadratic through both ends and its bent middle.
            const h = at(mix([from, rest[0], end], [0.25, 0.5, 0.25]));
            return `Q ${pt([2 * h[0] - (f[0] + t[0]) / 2, 2 * h[1] - (f[1] + t[1]) / 2])} ${pt(t)}`;
          }
          // The cubic through both ends and its bent thirds.
          const one = at(mix([from, ...rest], [8 / 27, 12 / 27, 6 / 27, 1 / 27]));
          const two = at(mix([from, ...rest], [1 / 27, 6 / 27, 12 / 27, 8 / 27]));
          const a = [0, 1].map((k) => 27 * one[k] - 8 * f[k] - t[k]);
          const b = [0, 1].map((k) => 27 * two[k] - f[k] - 8 * t[k]);
          const c1 = [0, 1].map((k) => (2 * a[k] - b[k]) / 18);
          const c2 = [0, 1].map((k) => (2 * b[k] - a[k]) / 18);
          return `C ${pt(c1)} ${pt(c2)} ${pt(t)}`;
        })
        .join(' ');
    return art
      .replace(/ d="([^"]*)"/g, (_, d) => ` d="${path(d)}"`)
      .replace(/cx="([^"]*)" cy="([^"]*)"/g, (_, x, y) => {
        const [tx, ty] = move(+x, +y);
        return `cx="${n(tx)}" cy="${n(ty)}"`;
      });
  }

  // SVG markup of one cast member in a pose.
  function figure(member, poses) {
    const posed = leveled(poses, member.level);
    const { matrices, opacities } = layout(posed);
    let svg = '';
    PARTS.forEach((part, i) => {
      const art =
        part.elbow && posed[i].bend && member.art[i]
          ? bent(member.art[i], part, posed[i].bend)
          : member.art[i];
      if (art && opacities[i] > 0)
        svg += `<g transform="matrix(${format(matrices[i])})" opacity="${opacities[i].toFixed(3)}">${art}</g>`;
    });
    return svg;
  }

  window.WildcardAvatar = { pose, perform, figure, bent };
})();
