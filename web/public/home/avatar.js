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

  function layout(poses) {
    const matrices = new Array(PARTS.length);
    const opacities = new Array(PARTS.length);
    // How opaque each part's children are drawn: its own opacity and its parents'.
    const carried = new Array(PARTS.length);
    // What each part's children move with: past the elbow for a bent arm.
    const carriers = new Array(PARTS.length);
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
        matrices[i] = multiply(carriers[j], m);
        carried[i] = q.opacity * carried[j];
      } else {
        matrices[i] = m;
        carried[i] = q.opacity;
      }
      opacities[i] = carried[i];
      carriers[i] =
        part.elbow && q.bend ? multiply(matrices[i], turn(q.bend, part.elbow.at)) : matrices[i];
    };
    PARTS.forEach((_, i) => place(i));
    return { matrices, opacities, carriers };
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
    // A curve's points cut where it leaves the upper arm, so a piece there stays as drawn
    // (Bend's pieces): refitted whole, a curve from the shoulder would turn at the shoulder too.
    const edge = middle - 0.15;
    const split = (points, t) => {
      let row = points;
      const [head, tail] = [[], []];
      while (row.length) {
        head.push(row[0]);
        tail.unshift(row[row.length - 1]);
        row = row.slice(1).map((to, j) => [0, 1].map((k) => row[j][k] + (to[k] - row[j][k]) * t));
      }
      return [head, tail];
    };
    const side = (points, t) => {
      const p = split(points, t)[0].at(-1);
      return along(p[0], p[1]) - edge;
    };
    const pieces = (points) => {
      const cuts = [];
      for (let step = 0; step < 16; step++) {
        let [low, high] = [step / 16, (step + 1) / 16];
        if (side(points, low) < 0 === side(points, high) < 0) continue;
        for (let k = 0; k < 40; k++) {
          const half = (low + high) / 2;
          if (side(points, low) < 0 === side(points, half) < 0) low = half;
          else high = half;
        }
        cuts.push((low + high) / 2);
      }
      const out = [];
      let [rest, done] = [points, 0];
      for (const cut of cuts) {
        const [head, tail] = split(rest, (cut - done) / (1 - done));
        out.push(head);
        [rest, done] = [tail, cut];
      }
      return [...out, rest];
    };
    const path = (d) =>
      segments(d)
        .flatMap(([command, from, ...rest]) =>
          command === 'Q' || command === 'C'
            ? pieces([from, ...rest]).map(([start, ...points]) => [command, start, ...points])
            : [[command, from, ...rest]],
        )
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

  const invert = ([a, b, c, d, e, f]) => {
    const det = a * d - b * c;
    return [d / det, -b / det, -c / det, a / det, (c * f - d * e) / det, (b * e - a * f) / det];
  };

  // A body's art as one black shape: where a shoulder's edge stays off it.
  const black = (art) =>
    art
      .replace(/\s(?:fill-)?opacity="[^"]*"/g, '')
      .replace(/\sfill="(?!none)[^"]*"/g, ' fill="#000"')
      .replace(/\sstroke="[^"]*"/g, ' stroke="none"');

  // Each frame's masks get ids of their own, so figures on one page never share one.
  let masks = 0;

  // A path's subpaths as points, its curves in short straight steps.
  function subpaths(d) {
    const out = [];
    const steps = 16;
    for (const [command, from, ...rest] of segments(d)) {
      if (command === 'M') {
        out.push([rest[0]]);
        continue;
      }
      if (!out.length) out.push([from]);
      const line = out[out.length - 1];
      if (command === 'L') line.push(rest[0]);
      else if (command === 'Z') line.push(line[0]);
      else
        for (let k = 1; k <= steps; k++) {
          const t = k / steps;
          const u = 1 - t;
          const [c1, c2, end] = command === 'Q' ? [rest[0], null, rest[1]] : rest;
          line.push(
            [0, 1].map((a) =>
              command === 'Q'
                ? u * u * from[a] + 2 * u * t * c1[a] + t * t * end[a]
                : u ** 3 * from[a] +
                  3 * u * u * t * c1[a] +
                  3 * u * t * t * c2[a] +
                  t ** 3 * end[a],
            ),
          );
        }
    }
    return out;
  }

  // A body's filled shapes as tests of whether a point lies in them, in the body's own space.
  function filled(art) {
    const number = (tag, name) => +(tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1] ?? 0);
    const tests = [];
    for (const tag of art.match(/<(?:path|circle|ellipse|rect)\b[^>]*>/g) ?? []) {
      const fill = tag.match(/\sfill="([^"]*)"/)?.[1];
      if (fill === 'none' || tag.includes('data-edge')) continue;
      if (tag.startsWith('<circle') || tag.startsWith('<ellipse')) {
        const [cx, cy] = [number(tag, 'cx'), number(tag, 'cy')];
        const [rx, ry] = tag.startsWith('<circle')
          ? [number(tag, 'r'), number(tag, 'r')]
          : [number(tag, 'rx'), number(tag, 'ry')];
        tests.push(([x, y]) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1);
      } else if (tag.startsWith('<rect')) {
        const [rx, ry, w, h] = ['x', 'y', 'width', 'height'].map((name) => number(tag, name));
        tests.push(([x, y]) => x > rx && x < rx + w && y > ry && y < ry + h);
      } else {
        const rings = subpaths(tag.match(/\sd="([^"]*)"/)?.[1] ?? '');
        // Non-zero winding, a shape's subpaths together, as the app fills them.
        tests.push(([x, y]) => {
          let winding = 0;
          for (const ring of rings)
            for (let k = 0; k < ring.length; k++) {
              const [a, b] = [ring[k], ring[(k + 1) % ring.length]];
              const cross = (b[0] - a[0]) * (y - a[1]) - (x - a[0]) * (b[1] - a[1]);
              if (a[1] <= y && b[1] > y && cross > 0) winding++;
              else if (a[1] > y && b[1] <= y && cross < 0) winding--;
            }
          return winding !== 0;
        });
      }
    }
    return (point) => tests.some((test) => test(point));
  }

  // `d` without what lies where `over` holds, cut along its centreline, so each piece ends
  // round where it stops (CGPath's lineSubtracting in the app). Unchanged when nothing is cut.
  function cut(d, over) {
    const step = 0.25;
    const pieces = [];
    let changed = false;
    for (const line of subpaths(d)) {
      let piece = over(line[0]) ? null : [line[0]];
      changed ||= piece === null;
      for (let k = 1; k < line.length; k++) {
        const [a, b] = [line[k - 1], line[k]];
        const n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / step));
        const at = (t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
        for (let j = 1; j <= n; j++) {
          const [t0, t1] = [(j - 1) / n, j / n];
          const inside = over(at(t1));
          if (inside === (piece === null)) {
            if (piece) piece.push(at(t1));
            continue;
          }
          // The point where the line crosses, halved down to well under a pixel.
          let [low, high] = [t0, t1];
          for (let h = 0; h < 20; h++) {
            const mid = (low + high) / 2;
            if (over(at(mid)) === inside) high = mid;
            else low = mid;
          }
          changed = true;
          if (piece) {
            piece.push(at(high));
            pieces.push(piece);
            piece = null;
          } else piece = [at(high), at(t1)];
        }
      }
      if (piece) pieces.push(piece);
    }
    if (!changed) return d;
    return pieces
      .filter((piece) => piece.length > 1)
      .map((piece) => 'M ' + piece.map((p) => p.map((v) => v.toFixed(3)).join(' ')).join(' L '))
      .join(' ');
  }

  // An arm's art with its sleeves' edges kept off its body and within its shoulder's reach
  // (rig.json's `shoulder`), as the app's FigureDrawing does: the edge shows only where the
  // arm leaves the body, and there it joins the body's outline.
  // Each sleeve's outline stops where it lies on the body at the shoulder's top (the reach's
  // half above the pivot), so a raised arm leaves no end of it on the chest.
  function shoulder(art, member, i, matrices) {
    const part = PARTS[i];
    if (!part.shoulder || !art.includes('data-edge=""')) return art;
    const j = INDEX[part.parent];
    member.black ??= {};
    member.black[j] ??= black(member.art[j] ?? '');
    member.filled ??= {};
    member.filled[j] ??= filled(member.art[j] ?? '');
    const id = `wc-shoulder-${(masks = (masks + 1) % 1e9)}`;
    const [px, py] = part.pivot;
    const [a, b, c, d, e, f] = multiply(invert(matrices[j]), matrices[i]);
    const over = ([x, y]) =>
      y < py &&
      Math.hypot(x - px, y - py) < part.shoulder &&
      member.filled[j]([a * x + c * y + e, b * x + d * y + f]);
    art = art.replace(
      /(<path data-outline=""[^>]*\sd=")([^"]*)"/g,
      (_, head, line) => `${head}${cut(line, over)}"`,
    );
    return (
      `<mask id="${id}" maskUnits="userSpaceOnUse" x="-500" y="-500" width="1240" height="1320">` +
      `<circle cx="${px}" cy="${py}" r="${part.shoulder}" fill="#fff"/>` +
      `<g transform="matrix(${format(multiply(invert(matrices[i]), matrices[j]))})">${member.black[j]}</g>` +
      `</mask>` +
      art.replaceAll('data-edge=""', `mask="url(#${id})"`)
    );
  }

  // SVG markup of one cast member in a pose.
  function figure(member, poses) {
    const posed = leveled(poses, member.level);
    const { matrices, opacities } = layout(posed);
    let svg = '';
    PARTS.forEach((part, i) => {
      const drawn =
        part.elbow && posed[i].bend && member.art[i]
          ? bent(member.art[i], part, posed[i].bend)
          : member.art[i];
      if (!drawn || !(opacities[i] > 0)) return;
      const art = shoulder(drawn, member, i, matrices);
      svg += `<g transform="matrix(${format(matrices[i])})" opacity="${opacities[i].toFixed(3)}">${art}</g>`;
    });
    return svg;
  }

  window.WildcardAvatar = { pose, perform, figure, bent, layout };
})();
