// Wildcard wordmark, variant B 冲线 (approved by Tracy 2026-10-23).
// The word sprints in leaning, dips its chest into a vertical tape, the tape breaks and
// topples under gravity, the word brakes and rocks back upright. About 1 s.
// Usage: playWordmarkB(wordEl, { tapeColor, floorY, onBreak, onSettle })
//   wordEl: an element holding the text (e.g. <h1>WILDCARD</h1>), already in its final place.
//   floorY: page-relative y (px) where the tape is anchored at the bottom; default 2.5 word heights below.
//   onBreak: called once when the tape breaks (the app's haptic moment).
//   onSettle: called ~0.2 s after the break (bring in the slogan and buttons then).
// Honours prefers-reduced-motion: no tape, the word just fades in.
(function (global) {
  const STEP = 1 / 240;
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const rad = (d) => (d * Math.PI) / 180;

  class Spring {
    constructor(x, response, damping) {
      this.x = x;
      this.v = 0;
      this.target = x;
      this.set(response, damping);
    }
    set(response, damping) {
      this.w = (2 * Math.PI) / response;
      this.z = damping;
    }
    step(h) {
      const a = -this.w * this.w * (this.x - this.target) - 2 * this.z * this.w * this.v;
      this.v += a * h;
      this.x += this.v * h;
    }
  }

  // The tape: a Verlet rope that pulls but never pushes.
  class Rope {
    constructor(x0, y0, x1, y1, n) {
      this.p = [];
      this.c = [];
      this.alpha = 1;
      for (let i = 0; i < n; i++) {
        const f = i / (n - 1);
        const x = x0 + (x1 - x0) * f,
          y = y0 + (y1 - y0) * f;
        this.p.push({ x, y, px: x, py: y, pin: false });
      }
      const seg = Math.hypot(x1 - x0, y1 - y0) / (n - 1);
      for (let i = 0; i < n - 1; i++) this.c.push({ a: i, b: i + 1, r: seg * 0.985 });
      this.p[0].pin = true;
      this.p[n - 1].pin = true;
    }
    breakAt(i) {
      this.c = this.c.filter((c) => c.a !== i);
    }
    kick(i, vx, vy, h) {
      const p = this.p[i];
      p.px = p.x - vx * h;
      p.py = p.y - vy * h;
    }
    step(h, collide, floorY, G) {
      for (const p of this.p) {
        if (p.pin) continue;
        const vx = (p.x - p.px) * 0.992,
          vy = (p.y - p.py) * 0.992;
        p.px = p.x;
        p.py = p.y;
        p.x += vx;
        p.y += vy + G * h * h;
      }
      for (let k = 0; k < 24; k++) {
        for (const c of this.c) {
          const a = this.p[c.a],
            b = this.p[c.b];
          const dx = b.x - a.x,
            dy = b.y - a.y,
            d = Math.hypot(dx, dy) || 1e-6;
          if (d <= c.r) continue;
          const diff = (d - c.r) / d;
          const wa = a.pin ? 0 : b.pin ? 1 : 0.5,
            wb = b.pin ? 0 : a.pin ? 1 : 0.5;
          a.x += dx * diff * wa;
          a.y += dy * diff * wa;
          b.x -= dx * diff * wb;
          b.y -= dy * diff * wb;
        }
        collide(this);
        for (const p of this.p)
          if (p.y > floorY) {
            p.y = floorY;
            p.px = p.x - (p.x - p.px) * 0.6;
          }
      }
    }
    draw(ctx, color, lw) {
      if (this.alpha <= 0) return;
      ctx.save();
      ctx.globalAlpha = this.alpha;
      ctx.strokeStyle = color;
      ctx.lineWidth = lw;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.beginPath();
      let last = -2;
      for (const c of this.c) {
        const a = this.p[c.a],
          b = this.p[c.b];
        if (c.a !== last) ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        last = c.b;
      }
      ctx.stroke();
      ctx.restore();
    }
    maxOffsetX(x) {
      let m = 0;
      for (const p of this.p) m = Math.max(m, p.x - x);
      return m;
    }
  }

  function playWordmarkB(word, opts = {}) {
    const color =
      opts.tapeColor ||
      getComputedStyle(document.documentElement).getPropertyValue('--sig').trim() ||
      '#079BB8';
    const onBreak = opts.onBreak || (() => {}),
      onSettle = opts.onSettle || (() => {});
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    word.style.transformOrigin = '50% 86%';
    if (reduce) {
      word.style.transition = 'opacity .25s';
      word.style.opacity = 0;
      requestAnimationFrame(() => {
        word.style.opacity = 1;
        onSettle();
      });
      return;
    }

    // Measure the text itself (not the block) in page coordinates.
    const range = document.createRange();
    range.selectNodeContents(word);
    const r = range.getBoundingClientRect();
    const sx = window.scrollX,
      sy = window.scrollY;
    const right = r.right + sx,
      top = r.top + sy,
      hgt = r.height;
    const capTop = top + 0.15 * hgt,
      baseline = top + 0.86 * hgt,
      midY = top + 0.52 * hgt;
    const floorY = opts.floorY != null ? opts.floorY : top + hgt * 3.5;
    const tapeTop = Math.max(sy - 12, top - hgt * 2.5);
    const tapeX = right - r.width * 0.48;
    // Every distance and speed is in the mockup's units (a 221pt-wide word on a 390pt phone), scaled to this word's size,
    // so a big desktop headline takes the same time and brakes as hard as the phone one.
    const k = opts.scale || r.width / 221,
      G = 3000 * k;

    // A canvas over the page, sized to the area the tape moves in.
    const pad = 40,
      cx0 = r.left + sx - pad,
      cy0 = tapeTop - pad;
    const cw = Math.min(document.documentElement.clientWidth + sx - cx0, r.width * 2 + pad * 2);
    const ch = floorY - cy0 + pad;
    const canvas = document.createElement('canvas');
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    Object.assign(canvas.style, {
      position: 'absolute',
      left: cx0 + 'px',
      top: cy0 + 'px',
      width: cw + 'px',
      height: ch + 'px',
      pointerEvents: 'none',
      zIndex: 3,
    });
    canvas.width = Math.round(cw * dpr);
    canvas.height = Math.round(ch * dpr);
    canvas.setAttribute('aria-hidden', 'true');
    document.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, -cx0 * dpr, -cy0 * dpr);

    const v0 = 900 * k,
      brakeAt = 90 * k;
    const rope = new Rope(tapeX, tapeTop, tapeX, floorY, 44);
    const lean = new Spring(-14, 0.34, 0.5);
    const w = (2 * Math.PI) / 0.45;
    let o = -(right + 24 * k),
      ov = v0,
      braking = false,
      broke = false,
      brokeAt = 0,
      dipUntil = -1,
      bob = 0,
      t = 0,
      settled = false;
    const collide = (rp) => {
      const tan = Math.tan(rad(lean.x));
      for (const p of rp.p) {
        if (p.pin || p.y < capTop || p.y > baseline) continue;
        const front = right + o + tan * (p.y - baseline) + 2;
        if (p.x < front && p.x > front - 70 * k) p.x = front;
      }
    };
    const step = (h) => {
      t += h;
      if (!braking) {
        o += v0 * h;
        if (o >= -brakeAt) braking = true;
      } else {
        const a = -w * w * o - 2 * w * ov;
        ov += a * h;
        o += ov * h;
      }
      if (!broke && right + o > tapeX && dipUntil < 0) {
        dipUntil = t + 0.08;
        lean.target = -24;
        lean.set(0.16, 0.8);
      }
      if (dipUntil > 0 && t > dipUntil && lean.target !== 0) {
        lean.target = 0;
        lean.set(0.36, 0.5);
      }
      lean.step(h);
      bob = braking ? bob * 0.85 : -5 * k * Math.abs(Math.sin((Math.PI * t) / 0.14));
      rope.step(h, collide, floorY, G);
      if (!broke && rope.maxOffsetX(tapeX) > 16 * k) {
        broke = true;
        brokeAt = t;
        onBreak();
        let best = 0,
          bd = 1e9;
        rope.p.forEach((p, i) => {
          const d = Math.abs(p.y - midY);
          if (d < bd) {
            bd = d;
            best = i;
          }
        });
        rope.breakAt(best);
        rope.p[0].pin = false;
        rope.p.forEach((p, i) => {
          if (p.pin) return;
          const f = i > best ? clamp((floorY - p.y) / (floorY - midY), 0, 1) : 0.6;
          rope.kick(i, 650 * k * f, -80 * k * f, h);
        });
      }
      if (broke) {
        rope.alpha = 1 - clamp((t - brokeAt - 0.45) / 0.3, 0, 1);
        if (!settled && t - brokeAt > 0.2) {
          settled = true;
          onSettle();
        }
      }
    };
    const paint = () => {
      ctx.clearRect(cx0, cy0, cw, ch);
      rope.draw(ctx, color, Math.max(4, 4 * Math.sqrt(k)));
      word.style.transform = `translate(${o.toFixed(2)}px, ${bob.toFixed(2)}px) skewX(${lean.x.toFixed(2)}deg)`;
    };
    let last = performance.now(),
      acc = 0;
    step(0);
    paint();
    const frame = (now) => {
      acc += Math.min(0.05, (now - last) / 1000);
      last = now;
      while (acc >= STEP) {
        step(STEP);
        acc -= STEP;
      }
      paint();
      if (broke && t - brokeAt > 1.0) {
        canvas.remove();
        word.style.transform = '';
        return;
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  global.playWordmarkB = playWordmarkB;
})(window);
