#!/usr/bin/env python3
# 商店街 shopper: two shopping bags held in the character's fists (prop variant `shopping`) and the
# walk and stop moves that swing them. The bags hang from the hands as damped pendulums driven by
# where the hands really go (forward kinematics of the app's rig), so they lag, overshoot and
# settle instead of being glued to the arm.
import json, math, os

# Run `python3 ios/Packages/Avatar/Tools/shopping.py`; it rewrites art/prop/shopping and moves/shopping.
PLACEHOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../Sources/AvatarArt/Placeholder')
SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">\n{}\n</svg>\n'


def ticket(cx, cy, w, h, deg, ink, paper, opacity):
    # The Wildcard ticket (brand-logo b6), printed on the bag in the bag's own ink: an outlined
    # ticket with a half-round notch either side and the W, turned by `deg`, every point placed
    # here since the art's SVG subset has no transforms.
    import math
    r = math.radians(deg); c, s = math.cos(r), math.sin(r)
    P = lambda u, v: (round(cx + (u * w) * c - (v * h) * s, 2), round(cy + (u * w) * s + (v * h) * c, 2))
    f = lambda p: f"{p[0]} {p[1]}"
    kx, ky = 0.18, 0.18 * w / h
    rn = 0.13 * w
    ny, nv = 0.2, rn / h          # notch centre and half-height, in the ticket's units
    nu = rn / w * 1.33            # how far the notch bites in
    d = (f"M {f(P(-.5 + kx, -.5))} L {f(P(.5 - kx, -.5))} Q {f(P(.5, -.5))} {f(P(.5, -.5 + ky))} "
         f"L {f(P(.5, ny - nv))} C {f(P(.5 - nu, ny - nv))} {f(P(.5 - nu, ny + nv))} {f(P(.5, ny + nv))} "
         f"L {f(P(.5, .5 - ky))} Q {f(P(.5, .5))} {f(P(.5 - kx, .5))} L {f(P(-.5 + kx, .5))} "
         f"Q {f(P(-.5, .5))} {f(P(-.5, .5 - ky))} L {f(P(-.5, ny + nv))} "
         f"C {f(P(-.5 + nu, ny + nv))} {f(P(-.5 + nu, ny - nv))} {f(P(-.5, ny - nv))} "
         f"L {f(P(-.5, -.5 + ky))} Q {f(P(-.5, -.5))} {f(P(-.5 + kx, -.5))} Z")
    zig = [P(-.27, -.27), P(-.135, .1), P(0, -.27), P(.135, .1), P(.27, -.27)]
    dash = [P(-.3, ny), P(.3, ny)]
    sw = round(0.1 * w, 2)
    return '\n'.join([
        f'  <path d="{d}" fill="{paper}" stroke="{ink}" stroke-width="{sw}" stroke-linejoin="round" stroke-opacity="{opacity}"/>',
        f'  <path d="M {" L ".join(f(p) for p in zig)}" fill="none" stroke="{ink}" stroke-width="{round(0.13 * w, 2)}" stroke-linejoin="round" stroke-linecap="round" stroke-opacity="{opacity}"/>',
        f'  <path d="M {f(dash[0])} L {f(dash[1])}" fill="none" stroke="{ink}" stroke-width="{round(0.05 * w, 2)}" stroke-dasharray="1.6 1.6" stroke-opacity="{opacity}"/>',
    ])

def kraft(cx):
    # Kraft paper bag, 26 wide, 24 tall, a folded rim and a rope handle into the fist.
    l, r, t, b = cx - 17, cx + 17, 279, 310
    return '\n'.join([
        f'  <path d="M {cx - 10} {t + 1} Q {cx - 12} 262 {cx} 259 Q {cx + 12} 262 {cx + 10} {t + 1}" fill="none" stroke="#7A5A36" stroke-width="2.2" stroke-linecap="round"/>',
        f'  <path d="M {l} {t} L {r} {t} L {r + 1} {b - 2.5} Q {r + 1} {b} {r - 1.5} {b} L {l + 1.5} {b} Q {l - 1} {b} {l - 1} {b - 2.5} Z" fill="#D2AE80" stroke="#9C7748" stroke-width="2.2" stroke-linejoin="round"/>',
        f'  <path d="M {l + 0.6} {t + 1.1} L {r - 0.6} {t + 1.1} L {r - 0.5} {t + 6} L {l + 0.5} {t + 6} Z" fill="#C39C6C"/>',
        f'  <path d="M {l + 4} {t + 6} L {l + 3.4} {b - 1.5}" fill="none" stroke="#C39C6C" stroke-width="1.6" stroke-linecap="round"/>',
        f'  <path d="M {r - 4} {t + 6} L {r - 3.4} {b - 1.5}" fill="none" stroke="#E6CDA4" stroke-width="1.6" stroke-linecap="round"/>',
        ticket(cx + 0.5, t + 17.5, 16, 22, -8, '#5B4128', '#D2AE80', 0.85),
    ])

def boutique(cx):
    # Graphite boutique bag, narrower and taller, white rope handles and a white tag.
    l, r, t, b = cx - 14, cx + 14, 278, 311
    return '\n'.join([
        f'  <path d="M {cx - 9} {t + 1} Q {cx - 11} 262 {cx} 259 Q {cx + 11} 262 {cx + 9} {t + 1}" fill="none" stroke="#0E0F14" stroke-width="4.2" stroke-linecap="round"/>',
        f'  <path d="M {cx - 9} {t + 1} Q {cx - 11} 262 {cx} 259 Q {cx + 11} 262 {cx + 9} {t + 1}" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round"/>',
        f'  <path d="M {l} {t} L {r} {t} L {r + 0.8} {b - 2.5} Q {r + 0.8} {b} {r - 1.7} {b} L {l + 1.7} {b} Q {l - 0.8} {b} {l - 0.8} {b - 2.5} Z" fill="#1F2128" stroke="#0E0F14" stroke-width="2.2" stroke-linejoin="round"/>',
        f'  <path d="M {l + 0.8} {t + 4.6} L {r - 0.8} {t + 4.6}" fill="none" stroke="#3A3E4A" stroke-width="1.4"/>',
        f'  <path d="M {l + 3.6} {t + 7} L {l + 3.2} {b - 2}" fill="none" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-opacity="0.18"/>',
        ticket(cx + 0.5, t + 18, 15, 21, -8, '#FFFFFF', '#1F2128', 0.92),
    ])

GRIP_R = ('  <circle cx="170.4" cy="264" r="10.8" fill="#F5CDAE" stroke="#B89A8B" stroke-width="2.64"/>\n'
          '  <path d="M 163.6 260.49 Q 170.95 258.44 176.58 264.21" fill="none" stroke="#B89A8B" stroke-width="2"/>')
GRIP_L = ('  <circle cx="69.6" cy="264" r="10.8" fill="#F5CDAE" stroke="#B89A8B" stroke-width="2.64"/>\n'
          '  <path d="M 76.4 260.49 Q 69.05 258.44 63.42 264.21" fill="none" stroke="#B89A8B" stroke-width="2"/>')

ART = {'propL': SVG.format(kraft(69.6)), 'propR': SVG.format(boutique(170.4)),
       'gripL': SVG.format(GRIP_L), 'grip': SVG.format(GRIP_R)}

# ---------- kinematics of the app's rig ----------
ROOT, TORSO = (120, 312), (120, 284.4)
ARM = {'L': dict(pivot=(92.4, 222), elbow=(78.6, 238.8), hand=(69.6, 264)),
       'R': dict(pivot=(147.6, 222), elbow=(161.4, 238.8), hand=(170.4, 264))}

def rot(p, c, deg):
    r = math.radians(deg); s, k = math.sin(r), math.cos(r)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + k * x - s * y, c[1] + s * x + k * y)

def hand_at(side, q):
    a = ARM[side]
    h = rot(a['hand'], a['elbow'], q['bend' + side])          # forearm past the elbow
    h = rot(h, a['pivot'], q['arm' + side])                    # the arm at the shoulder
    h = rot(h, TORSO, q['torso'])                              # the torso
    return (h[0] + q['x'], h[1] + q['y'])                      # the root

# ---------- the walk ----------
T = 0.9           # two steps
SWING = 9.0       # arms, degrees, a little less than empty-handed: the bags have weight
def walk_q(t):
    w = 2 * math.pi * t / T
    s = math.sin(w)
    lag = math.sin(w - 2 * math.pi * 0.09 / T)
    return dict(
        armL=SWING * s, armR=SWING * s,
        bendL=0.55 * SWING * (lag - s), bendR=0.55 * SWING * (lag - s),
        torso=-1.6 * s, x=1.4 * s,
        y=-3.2 * abs(math.sin(w)) ** 0.8,
        legLy=-5 * max(0, math.sin(w)) ** 1.5, legRy=-5 * max(0, -math.sin(w)) ** 1.5,
        legL=-4 * max(0, math.sin(w)), legR=4 * max(0, -math.sin(w)),
        scaleY=1 - 0.025 * (1 - abs(math.sin(w))),
        head=2.2 * math.sin(w - 0.6), shadow=1 - 0.06 * abs(math.sin(w)),
    )

BAG = {'L': dict(l=28.0, period=0.62, zeta=0.22), 'R': dict(l=28.0, period=0.56, zeta=0.26)}
DT = 1 / 600

def simulate(side, q_at, dur, phi0=0.0, w0=0.0, push=None):
    """Angle from vertical (deg, the rig's sign) of a bag hanging from `side`'s hand, sampled."""
    b = BAG[side]
    omega = 2 * math.pi / b['period']; g = omega ** 2 * b['l']; c = 2 * b['zeta'] * omega
    phi, w = math.radians(phi0), math.radians(w0)
    out = []
    n = int(round(dur / DT))
    def acc(t):
        e = 1e-3
        p0, p1, p2 = hand_at(side, q_at(t - e)), hand_at(side, q_at(t)), hand_at(side, q_at(t + e))
        ax = (p2[0] - 2 * p1[0] + p0[0]) / e ** 2
        ay = (p2[1] - 2 * p1[1] + p0[1]) / e ** 2
        if push: ax += push(t)
        return ax, ay
    for i in range(n + 1):
        t = i * DT
        out.append((t, math.degrees(phi), math.degrees(w)))
        ax, ay = acc(t)
        # Bottom of the bag at hand + (-l sin, l cos): positive turns it clockwise, bottom left.
        alpha = (-(g - ay) * math.sin(phi) + ax * math.cos(phi)) / b['l'] - c * w
        w += alpha * DT; phi += w * DT
    return out

def keys(fn, dur, n, ease=None):
    out = []
    for i in range(n + 1):
        t = dur * i / n
        k = {'t': round(t, 4), 'v': round(fn(t), 3)}
        if ease and i: k['ease'] = ease
        out.append(k)
    return out

def track(part, channel, ks): return {'part': part, 'channel': channel, 'keys': ks}

def walk_clip():
    # Run the bags for a while so the loop we keep is the steady swing, which wraps cleanly.
    warm = 8 * T
    bags = {}
    for side in 'LR':
        s = simulate(side, lambda t: walk_q(t % T), warm + T)
        tail = [(t - warm, p) for t, p, _ in s if t >= warm - 1e-9]
        bags[side] = tail
    def phi_at(side, t):
        tail = bags[side]
        i = min(len(tail) - 1, int(round(t / DT)))
        return tail[i][1]
    N = 24
    tr = []
    q = walk_q
    tr.append(track('root', 'y', keys(lambda t: q(t)['y'], T, N)))
    tr.append(track('root', 'x', keys(lambda t: q(t)['x'], T, N)))
    tr.append(track('root', 'scaleY', keys(lambda t: q(t)['scaleY'], T, N)))
    tr.append(track('torso', 'rotation', keys(lambda t: q(t)['torso'], T, N)))
    tr.append(track('head', 'rotation', keys(lambda t: q(t)['head'], T, N)))
    tr.append(track('legL', 'y', keys(lambda t: q(t)['legLy'], T, N)))
    tr.append(track('legR', 'y', keys(lambda t: q(t)['legRy'], T, N)))
    tr.append(track('legL', 'rotation', keys(lambda t: q(t)['legL'], T, N)))
    tr.append(track('legR', 'rotation', keys(lambda t: q(t)['legR'], T, N)))
    tr.append(track('shadow', 'scaleX', keys(lambda t: q(t)['shadow'], T, N)))
    for side, part in (('L', 'armL'), ('R', 'armR')):
        tr.append(track(part, 'rotation', keys(lambda t, s=side: q(t)['arm' + s], T, N)))
        tr.append(track(part, 'bend', keys(lambda t, s=side: q(t)['bend' + s], T, N)))
        # The bag's own turn is its swing less everything carrying it.
        tr.append(track('prop' + side, 'rotation', keys(
            lambda t, s=side: phi_at(s, t) - (q(t)['torso'] + q(t)['arm' + s] + q(t)['bend' + s]), T, N)))
    amp = {s: max(abs(p) for _, p in bags[s]) for s in 'LR'}
    seam = {s: abs(bags[s][0][1] - bags[s][-1][1]) for s in 'LR'}
    print('walk bag swing ±', amp, 'loop seam', seam)
    start = {s: simulate(s, lambda t: walk_q(t % T), warm + T)[int(round((warm + T) / DT))][1:] for s in 'LR'}
    return {'version': 1, 'name': 'shopping-walk', 'duration': T, 'loops': True, 'holds': 'shopping', 'tracks': tr}, start

def sm(a, b, t):
    f = min(1, max(0, (t - a) / (b - a))); return f * f * (3 - 2 * f)

def spot_clip(start):
    # Walking, it stops: something good in the window. The last step plants and the bags swing on
    # ahead; a double take (brows up, eyes wide), then star eyes, a sparkle, mouth open, fists up
    # and two little hops on the spot that set the bags bouncing; then it settles, still smiling.
    D = 2.6
    hop = lambda t, t0: -8 * math.sin(math.pi * (t - t0) / 0.24) if t0 <= t < t0 + 0.24 else 0
    def q(t):
        z = walk_q(0)
        down = 1 - sm(0, 0.3, t)
        up = sm(0.36, 0.72, t) * (1 - sm(1.85, 2.3, t))
        wig = math.sin(2 * math.pi * (t - 1.12) / 0.5) * sm(1.1, 1.25, t) * (1 - sm(1.6, 1.8, t))
        y = (-2.2 * math.sin(math.pi * min(1, t / 0.3)) if t < 0.3 else 0) + hop(t, 0.6) + hop(t, 0.86)
        return dict(armL=z['armL'] * down - 12 * up, armR=z['armR'] * down + 12 * up,
                    bendL=-28 * up, bendR=28 * up, torso=2.2 * wig, x=0, y=y, head=4 * wig)
    def push(t):
        # The body was moving at walking pace and stops over 0.2 s: the hands decelerate.
        return 520 * math.sin(math.pi * t / 0.2) if t < 0.2 else 0
    N = 78
    sims = {s: simulate(s, q, D, start[s][0], start[s][1], push) for s in 'LR'}
    def phi(s, t): return sims[s][min(len(sims[s]) - 1, int(round(t / DT)))][1]
    fade = lambda t: 1 - sm(D - 0.5, D, t)
    def squash(t):
        for t0 in (0.6, 0.86):
            if t0 - 0.06 <= t < t0: return 1 - 0.06 * sm(t0 - 0.06, t0 - 0.03, t)
            if t0 + 0.2 <= t < t0 + 0.3: return 1 - 0.06 * (1 - sm(t0 + 0.24, t0 + 0.3, t))
        return 1 - 0.03 * math.sin(math.pi * t / 0.3) if t < 0.3 else 1
    K = lambda pts: [dict(t=a, v=b) for a, b in pts]
    tr = [
        track('root', 'y', keys(lambda t: q(t)['y'], D, N)),
        track('root', 'scaleY', keys(squash, D, N)),
        track('torso', 'rotation', keys(lambda t: q(t)['torso'], D, N)),
        track('head', 'rotation', keys(lambda t: q(t)['head'], D, N)),
        track('head', 'y', K([(0, 0), (0.24, 0), (0.34, -4), (0.5, -2), (1.9, -2), (2.2, 0)])),
        track('brows', 'y', K([(0, 0), (0.24, 0), (0.3, -7), (1.9, -6), (2.1, 0)])),
        track('eyes', 'scaleY', K([(0, 1), (0.24, 1), (0.3, 1.3), (0.4, 1.3), (0.42, 1), (D, 1)])),
        track('eyes', 'scaleX', K([(0, 1), (0.24, 1), (0.3, 1.14), (0.4, 1.14), (0.42, 1), (D, 1)])),
        track('eyes', 'opacity', K([(0, 1), (0.4, 1), (0.42, 0), (1.95, 0), (1.98, 1), (D, 1)])),
        track('stars', 'opacity', K([(0, 0), (0.4, 0), (0.42, 1), (1.95, 1), (1.98, 0), (D, 0)])),
        track('stars', 'scaleX', K([(0, 1), (0.4, 0.2), (0.56, 1.18), (0.76, 0.95), (1.0, 1.1), (1.24, 0.95), (1.5, 1.08), (1.75, 1), (D, 1)])),
        track('stars', 'scaleY', K([(0, 1), (0.4, 0.2), (0.56, 1.18), (0.76, 0.95), (1.0, 1.1), (1.24, 0.95), (1.5, 1.08), (1.75, 1), (D, 1)])),
        track('sparkle', 'opacity', K([(0, 0), (0.46, 0), (0.5, 1), (1.8, 1), (1.95, 0), (D, 0)])),
        track('sparkle', 'scaleX', K([(0, 0.3), (0.46, 0.3), (0.62, 1.15), (0.9, 0.9), (1.2, 1.1), (1.5, 0.92), (1.8, 1), (D, 1)])),
        track('sparkle', 'scaleY', K([(0, 0.3), (0.46, 0.3), (0.62, 1.15), (0.9, 0.9), (1.2, 1.1), (1.5, 0.92), (1.8, 1), (D, 1)])),
        track('mouthOpen', 'opacity', K([(0, 0), (0.4, 0), (0.42, 1), (2.0, 1), (2.03, 0), (D, 0)])),
        track('mouthSmile', 'opacity', K([(0, 1), (0.4, 1), (0.42, 0), (2.0, 0), (2.03, 1), (D, 1)])),
        track('shadow', 'scaleX', keys(lambda t: 1 + q(t)['y'] / 80, D, N)),
    ]
    for side, part in (('L', 'armL'), ('R', 'armR')):
        tr.append(track(part, 'rotation', keys(lambda t, s=side: q(t)['arm' + s], D, N)))
        tr.append(track(part, 'bend', keys(lambda t, s=side: q(t)['bend' + s], D, N)))
        tr.append(track('prop' + side, 'rotation', keys(
            lambda t, s=side: phi(s, t) * fade(t) - (q(t)['torso'] + q(t)['arm' + s] + q(t)['bend' + s]), D, N)))
    print('spot swing max', {s: max(abs(p) for _, p, _ in sims[s]) for s in 'LR'})
    return {'version': 1, 'name': 'shopping-spot', 'duration': D, 'loops': False, 'holds': 'shopping', 'tracks': tr}

def main():
    walk, start = walk_clip()
    spot = spot_clip(start)
    art = f'{PLACEHOLDER}/art/prop/shopping'
    moves = f'{PLACEHOLDER}/moves/shopping'
    os.makedirs(art, exist_ok=True)
    os.makedirs(moves, exist_ok=True)
    for name, svg in ART.items():
        open(f'{art}/{name}.svg', 'w').write(svg)
    open(f'{art}/hold.json', 'w').write(json.dumps({'version': 1, 'level': ['armL', 'armR']}) + '\n')
    for clip, name in ((walk, 'walk'), (spot, 'spot')):
        open(f'{moves}/{name}.json', 'w').write(json.dumps(clip, ensure_ascii=False, separators=(',', ':')) + '\n')

main()
