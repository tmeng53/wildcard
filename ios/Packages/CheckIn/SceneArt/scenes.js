
// Scene art and layout. Every scene uses the same plan:
// the scene's own stations for people whose sport matches; everyone else anywhere on the open floor; me front-centre.
const f1 = n => (+n).toFixed(1);
const THEMES = {
  track:  { name: '跑道',   sig: '#E65345', shade: '#C23B2E', wash: '#FCEDEB', text: '#B83325', on: '#FFFFFF' },
  pool:   { name: '泳池',   sig: '#079BB8', shade: '#067C93', wash: '#E2F5F9', text: '#066E83', on: '#FFFFFF' },
  gym:    { name: '健身房', sig: '#1F2128', shade: '#000000', wash: '#EEF0F2', text: '#1F2128', on: '#C6F432' },
  tennis: { name: '网球场', sig: '#4F6B22', shade: '#3B5119', wash: '#EEF2E4', text: '#41591B', on: '#FFFFFF' },
  climb:  { name: '攀岩馆', sig: '#8E4A2C', shade: '#6F3820', wash: '#F6EDE8', text: '#7A3E24', on: '#FFFFFF' },
};
// Zones: 4 spots per row, 2 rows; the first row listed is the one nearer the camera.
const Z = {
  rest:   { x0: 196, x1: 380, rows: [322, 284], seat: true },
  leave:  { x0: 12, x1: 168, rows: [640, 600], seat: true },
  done:   { x0: 222, x1: 380, rows: [640, 600] },
};
function zoneSpots(z) {
  const out = [];
  z.rows.forEach((y, r) => {
    // Eight evenly spaced columns, alternating rows, so a back-row face shows between two front-row faces.
    const step = (z.x1 - z.x0) / 8;
    for (let i = 0; i < 4; i++) out.push({ x: z.x0 + step * (2 * i + r + .5), y, seat: !!z.seat, r });
  });
  // Nearer row first, then the spot nearest the middle of the screen.
  return out.sort((a, b) => (a.r - b.r) || Math.abs(a.x - 195) - Math.abs(b.x - 195));
}
// Depth scale for a spot at y: nearer is bigger. Benches use it to put the seat at hip height.
const depthK = y => .21 + (.29 - .21) * Math.min(1, Math.max(0, (y - 280) / (640 - 280)));
const shade = (hex, k) => '#' + [1, 3, 5].map(i => Math.round(parseInt(hex.slice(i, i + 2), 16) * (1 - k)).toString(16).padStart(2, '0')).join('');
const BENCH = new Map(); // zone -> [top, edge] colours, set by benchBack
function benchBack(z, c, cd) { // remembers the bench colours; the backrest is drawn with its seat row
  BENCH.set(z, [c, cd]);
  return '';
}
function backrest(z, y) {
  const [c, cd] = BENCH.get(z) || ['#FFFFFF', '#D5DBE4']; let s = '';
  { const hip = y - 45 * depthK(y); s += `<rect x="${z.x0 - 6}" y="${(hip - 15).toFixed(1)}" width="${z.x1 - z.x0 + 12}" height="9" rx="3" fill="${c}"/><rect x="${z.x0 - 6}" y="${(hip - 8).toFixed(1)}" width="${z.x1 - z.x0 + 12}" height="2" fill="${cd}"/>`; }
  return s;
}
function benchFront(z, face) { // seat and front face, depth-sorted just behind the people on it
  const [top] = BENCH.get(z) || ['#FFFFFF'];
  return z.rows.map(y => { const hip = y - 45 * depthK(y), w = z.x1 - z.x0 + 12; return { y: y - .5, svg: backrest(z, y) +
    `<rect x="${z.x0 - 6}" y="${(y - 1).toFixed(1)}" width="${w}" height="3" rx="1.5" fill="#000" fill-opacity=".07"/>` +
    `<rect x="${z.x0 - 6}" y="${(hip + 1).toFixed(1)}" width="${w}" height="${(y - hip - 1.5).toFixed(1)}" rx="1.5" fill="${shade(face, .14)}"/>` +
    `<rect x="${z.x0 - 7}" y="${(hip - 2.5).toFixed(1)}" width="${w + 2}" height="5" rx="2.2" fill="${top}"/>` +
    `<rect x="${z.x0 - 7}" y="${(hip + 1.5).toFixed(1)}" width="${w + 2}" height="1.6" fill="${shade(face, .3)}"/>` }; });
}
const lane = (x0, x1, y) => ({ x0, x1, y });
// Soft square tiles, the floor every simple scene shares.
function tiles(y0, y1, bg, line, size = 64) {
  let s = `<rect x="0" y="${y0}" width="390" height="${y1 - y0}" fill="${bg}"/>`;
  for (let x = 2; x < 390; x += size) s += `<rect x="${x}" y="${y0}" width="2" height="${y1 - y0}" fill="${line}"/>`;
  for (let y = y0 + size * .7; y < y1; y += size) s += `<rect x="0" y="${f1(y)}" width="390" height="2" fill="${line}"/>`;
  return s;
}
// Rounded stand steps across the back, seen front on.
function steps(y0, n, h, top, face) {
  let s = '';
  for (let i = 0; i < n; i++) { const y = y0 + i * h; s += `<rect x="-4" y="${y}" width="398" height="${h}" fill="${face}"/><rect x="-4" y="${y}" width="398" height="5" rx="2.5" fill="${top}"/>`; }
  return s;
}
// A V4-style hurdle: two rounded posts and a bar, in soft grey.
const softHurdle = (x, y, c = '#C9CFD8') => `<g transform="translate(${x} ${y})"><rect x="-26" y="-30" width="9" height="34" rx="4.5" fill="${c}"/><rect x="17" y="-30" width="9" height="34" rx="4.5" fill="${c}"/><rect x="-30" y="-26" width="60" height="9" rx="4.5" fill="${c}"/><rect x="-30" y="-12" width="60" height="7" rx="3.5" fill="${c}"/></g>`;

const SCENES = {
  track() {
    let s = `<rect width="390" height="844" fill="#EAF2F7"/>`;
    // back: stands across the whole width
    s += steps(200, 6, 21, '#FFFFFF', '#DFE7EE');
    s += `<rect x="0" y="326" width="390" height="20" fill="#D5E4C2"/>`;
    s += softHurdle(60, 344, '#FFFFFF') + softHurdle(330, 344, '#FFFFFF');
    // track lanes, flat bands across the screen
    s += `<rect x="0" y="346" width="390" height="204" fill="#E65345"/>`;
    [346, 397, 448, 499, 550].forEach(y => s += `<rect x="0" y="${y - 1}" width="390" height="2.4" fill="#FFFFFF" fill-opacity=".85"/>`);
    [[1, 380], [2, 431], [3, 482], [4, 533]].forEach(([n, y]) => s += `<text x="372" y="${y - 6}" text-anchor="middle" font-family="Barlow Condensed,sans-serif" font-weight="700" font-size="20" fill="#FFFFFF" fill-opacity=".5">${n}</text>`);
    // front apron
    s += tiles(551, 851, '#F3F5F0', '#E4E9DC') + `<rect x="0" y="551" width="390" height="6" fill="#D9E3CC"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#D5DBE4');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 55, x1: 335, y0: 380, y1: 500 }], avoid: [], open: [{ x0: 0, x1: 390, y0: 480, y1: 650 }], lift: 36, floor: '#F3F5F0',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".08"><ellipse cx="110" cy="450" rx="190" ry="80"/><ellipse cx="290" cy="470" rx="190" ry="80"/></g>`,
      lampsTop: `<rect x="186" y="210" width="196" height="3" fill="#FFF3C4"/>`,
      stations: [
        { kind: 'jog', label: '慢跑', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 390), speed: 56 },
        { kind: 'jog', label: '慢跑', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 441), speed: 48 },
        { kind: 'jog', label: '慢跑', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 492), speed: 48, dir: -1 },
      ],
      sports: { run: ['jog'] },
    };
  },
  pool() {
    let s = `<rect width="390" height="844" fill="#E2F5F9"/>`;
    s += tiles(200, 266, '#EEF6F8', '#DCEBEF', 26);
    s += `<rect x="0" y="262" width="390" height="5" fill="#CFE3E9"/>` + tiles(267, 341, '#F7FAFB', '#E6EFF2', 37);
    s += `<g transform="translate(326 56)"><rect x="0" y="214" width="5" height="64" rx="2.5" fill="#FFFFFF"/><rect x="24" y="214" width="5" height="64" rx="2.5" fill="#FFFFFF"/><rect x="-4" y="208" width="37" height="10" rx="5" fill="#E65345"/><rect x="2" y="238" width="25" height="5" rx="2.5" fill="#FFFFFF"/><rect x="2" y="258" width="25" height="5" rx="2.5" fill="#FFFFFF"/></g>`;
    s += `<rect x="0" y="337" width="390" height="5" fill="#CFE3E9"/>`;
    s += `<rect x="0" y="342" width="390" height="134" fill="#5FC0D5"/>`;
    const laneY = [358, 391, 424, 457, 490, 523];
    for (let i = 0; i < 3; i++) { const y = 374 + i * 33; for (let x = 4; x < 390; x += 9) s += `<circle cx="${x}" cy="${y}" r="2.6" fill="${(x / 9 | 0) % 6 < 2 ? '#E65345' : '#FFFFFF'}"/>`; }
    for (let i = 0; i < 4; i++) s += `<rect x="20" y="${laneY[i] - 1}" width="350" height="2" fill="#067C93" fill-opacity=".22"/>`;
    s += `<rect x="0" y="474" width="390" height="10" fill="#CFE3E9"/>` + tiles(482, 848, '#F7FAFB', '#E6EFF2');
    s += benchBack(Z.leave, '#FFFFFF', '#CFE3E9');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { avoid: [], open: [{ x0: 0, x1: 390, y0: 474, y1: 650 }], lift: 36, floor: '#F7FAFB',
      bg: s, fronts: [],
      lamps: `<g fill="#BFF1FF" fill-opacity=".16"><rect x="0" y="342" width="390" height="134"/></g><g fill="#FFE9A8" fill-opacity=".1"><ellipse cx="90" cy="600" rx="140" ry="50"/><ellipse cx="300" cy="600" rx="140" ry="50"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><circle cx="120" cy="206" r="4"/><circle cx="270" cy="206" r="4"/></g>`,
      water: { y0: 342, y1: 476 },
      stations: [
        { kind: 'swim', label: '自由泳', kit: 'swim', clip: 'swim', n: 4, path: 'lanes', lanes: laneY.slice(0, 4).map(y => lane(36, 354, y + 6)), speed: 34, swim: true },
      ],
      sports: { swim: ['swim'] },
    };
  },
  gym() {
    const G1 = '#2B2E36', G2 = '#3D414B', V = '#C6F432';
    let s = `<rect width="390" height="844" fill="#F2F3F5"/>`;
    s += `<rect x="0" y="272" width="390" height="4" fill="#1F2128"/><rect x="0" y="276" width="390" height="3" fill="${V}"/>`;
    // clock and a small front desk on the wall line
    s += `<circle cx="300" cy="306" r="11" fill="#FFFFFF" stroke="${G1}" stroke-width="2.5"/><path d="M300 306 V299 M300 306 L305 309" stroke="${G1}" stroke-width="2" stroke-linecap="round"/>`;
    s += `<rect x="40" y="302" width="92" height="32" rx="6" fill="${G1}"/><rect x="40" y="302" width="92" height="6" rx="3" fill="${V}"/><text x="86" y="326" text-anchor="middle" font-family="Barlow Condensed,sans-serif" font-weight="700" font-size="12" fill="#FFFFFF" letter-spacing="1">FRONT DESK</text>`;
    s += tiles(334, 846, '#ECEEF1', '#DEE1E6') + `<rect x="0" y="334" width="390" height="4" fill="#D3D7DD"/>`;
    // dark rubber platforms only under the machines
    s += `<rect x="30" y="384" width="160" height="40" rx="8" fill="${G1}"/><rect x="206" y="384" width="160" height="40" rx="8" fill="${G1}"/>`;
    s += `<rect x="40" y="474" width="138" height="5" rx="2.5" fill="#C9CED6"/>`;
    for (let i = 0; i < 6; i++) s += `<rect x="${46 + i * 22}" y="465" width="6" height="11" rx="2" fill="${G1}"/><rect x="${56 + i * 22}" y="465" width="6" height="11" rx="2" fill="${G1}"/><rect x="${51 + i * 22}" y="469" width="6" height="3" fill="#A3A8B2"/>`;
    // station furniture
    const tread = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-4" width="52" height="10" rx="3" fill="${G2}"/><rect x="-24" y="-3" width="48" height="5" rx="2" fill="#1A1C21"/><rect x="18" y="-40" width="4" height="38" rx="2" fill="#70757F"/><rect x="10" y="-46" width="20" height="9" rx="2" fill="${G2}"/><rect x="13" y="-44" width="9" height="4" fill="${V}"/></g>`;
    const rack = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="21" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="-30" y="-2" width="60" height="4" rx="2" fill="#1A1C21"/></g>`;
    const mat = x => `<path d="M${x - 28} 516 L${x + 28} 516 L${x + 33} 532 L${x - 33} 532 Z" fill="#3D414B"/><path d="M${x + 24} 516 L${x + 28} 516 L${x + 33} 532 L${x + 28} 532 Z" fill="${V}"/>`;
    s += tread(70) + tread(146) + rack(246) + rack(322) + mat(250) + mat(326);
    s += benchBack(Z.leave, '#FFFFFF', '#D3D7DD');
    const bar = x => ({ y: 412.6, svg: `<rect x="${x - 32}" y="364" width="64" height="3" rx="1.5" fill="#A3A8B2"/>` });
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 420, y1: 500 }], avoid: [{ x0: 40, x1: 350, y0: 350, y1: 392 }, { x0: 40, x1: 178, y0: 440, y1: 456 }], open: [{ x0: 0, x1: 390, y0: 440, y1: 650 }], lift: 24, floor: '#ECEEF1',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".1"><ellipse cx="110" cy="440" rx="150" ry="60"/><ellipse cx="290" cy="460" rx="150" ry="60"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><rect x="60" y="204" width="90" height="4" rx="2"/><rect x="240" y="204" width="90" height="4" rx="2"/></g>`,
      stations: [
        { kind: 'treadmill', label: '跑步机', kit: 'run', clip: 'run', n: 2, path: 'still', spots: [[66, 409], [142, 409]] },
        { kind: 'squat', label: '深蹲', kit: 'strength', clip: 'squat', n: 2, path: 'still', spots: [[246, 412], [322, 412]], bar: true },
        { kind: 'dumbbell', label: '哑铃', kit: 'strength', clip: 'strength', n: 2, path: 'still', spots: [[80, 530], [150, 530]] },
        { kind: 'yoga', label: '瑜伽', kit: 'yoga', clip: 'yoga', n: 2, path: 'still', spots: [[250, 526], [326, 526]] },
      ],
      sports: { run: ['treadmill'], strength: ['squat', 'dumbbell'], yoga: ['yoga'] },
    };
  },
  tennis() {
    let s = `<rect width="390" height="844" fill="#EEF4F6"/>`;
    s += `<rect x="0" y="210" width="390" height="114" fill="#E6ECDD"/>`;
    for (let y = 210; y < 324; y += 16) for (let x = 0; x < 390; x += 16) s += `<path d="M${x} ${y} L${x + 16} ${y + 16} M${x + 16} ${y} L${x} ${y + 16}" stroke="#CBD5BB" stroke-width="1.2"/>`;
    s += `<g>${[0, 1, 2].map(r => `<rect x="236" y="${264 + r * 20}" width="160" height="20" fill="#DCE3D0"/><rect x="236" y="${264 + r * 20}" width="160" height="5" rx="2.5" fill="#FFFFFF"/>`).join('')}</g>`;
    s += `<rect x="0" y="324" width="390" height="236" fill="#6E8F38"/>`;
    s += `<path d="M24 336 H366 V500 H24 Z M54 336 V500 M336 336 V500 M54 376 H336 M54 460 H336 M195 376 V460" stroke="#FFFFFF" stroke-width="2.4" fill="none"/>`;
    s += tiles(560, 850, '#F0F3E9', '#E0E7D3') + `<rect x="0" y="556" width="390" height="6" fill="#5C7A2D"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#C9D3BB');
    const net = { lift: true, y: 418.5, svg: `<rect x="18" y="402" width="354" height="16" fill="#FFFFFF" fill-opacity=".28"/><path d="M18 402 H372" stroke="#FFFFFF" stroke-width="3"/>${Array.from({ length: 30 }, (_, i) => `<rect x="${20 + i * 12}" y="403" width="1" height="15" fill="#FFFFFF" fill-opacity=".5"/>`).join('')}<rect x="16" y="398" width="4" height="22" fill="#3B5119"/><rect x="370" y="398" width="4" height="22" fill="#3B5119"/>` };
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 70, x1: 330, y0: 346, y1: 470, avoid: [{ x0: 0, x1: 390, y0: 375, y1: 402 }] }], avoid: [], open: [{ x0: 0, x1: 390, y0: 480, y1: 650 }], lift: 30, floor: '#F0F3E9',
      bg: s, fronts: [net],
      lamps: `<g fill="#FFE9A8" fill-opacity=".13"><ellipse cx="195" cy="450" rx="230" ry="110"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><rect x="20" y="206" width="40" height="5" rx="2"/><rect x="330" y="206" width="40" height="5" rx="2"/></g>`,
      stations: [
        { kind: 'rally', label: '对打', kit: 'tennis', keepProp: true, clip: 'tennis', n: 4, path: 'still', spots: [[130, 376], [130, 492], [262, 376], [262, 492]], rally: true },
        { kind: 'serve', label: '发球', kit: 'tennis', keepProp: true, clip: 'tennis', n: 2, path: 'still', spots: [[40, 352], [350, 496]], serve: true },
      ],
      sports: { tennis: ['rally', 'serve'] },
    };
  },
  climb() {
    let s = `<rect width="390" height="844" fill="#EAD8CC"/>`;
    const HZ = 446;
    const P = [['M-10 196 L120 214 L104 330 L-10 312Z', '#F1E5DD'], ['M120 214 L250 190 L268 316 L104 330Z', '#E8D6CA'], ['M250 190 L400 222 L400 334 L268 316Z', '#EFE2D9'],
      [`M-10 312 L104 330 L96 ${HZ} L-10 ${HZ}Z`, '#E5D1C3'], [`M104 330 L268 316 L282 ${HZ} L96 ${HZ}Z`, '#EEDFD5'], [`M268 316 L400 334 L400 ${HZ} L282 ${HZ}Z`, '#E3CEBF']];
    P.forEach(([d, c]) => s += `<path d="${d}" fill="${c}" stroke="#F7EFE9" stroke-width="2"/>`);
    let k = 7; const r = () => (k = (k * 9301 + 49297) % 233280) / 233280;
    const routes = [['#8E4A2C', 132], ['#2B2E36', 177], ['#FFFFFF', 222], ['#C6F432', 267], ['#2D5BA0', 318], ['#E65345', 360]];
    routes.forEach(([c, x]) => { for (let y = 226; y < HZ - 20; y += 24) { const xx = x + (r() - .5) * 22, rr = 3.5 + r() * 3; s += `<ellipse cx="${f1(xx)}" cy="${y}" rx="${f1(rr * 1.3)}" ry="${f1(rr)}" transform="rotate(${f1(r() * 180)} ${f1(xx)} ${y})" fill="${c}" ${c === '#FFFFFF' ? 'stroke="#D9C3B5" stroke-width="1.2"' : ''}/>`; } });
    [132, 177, 222, 267].forEach(x => s += `<circle cx="${x}" cy="200" r="3" fill="#6F3820"/>`);
    s += `<rect x="0" y="${HZ - 6}" width="390" height="6" fill="#6F3820"/>` + tiles(HZ, HZ + 400, '#F2E9E2', '#E4D6CB');
    s += `<rect x="0" y="${HZ}" width="390" height="34" fill="#8E4A2C"/>${[100, 290].map(x => `<rect x="${x}" y="${HZ}" width="2" height="34" fill="#6F3820"/>`).join('')}<rect x="0" y="${HZ + 30}" width="390" height="4" fill="#6F3820"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#E0CFC2');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 482, y1: 482 }], avoid: [], open: [{ x0: 0, x1: 390, y0: 470, y1: 650 }], lift: 10, floor: '#F2E9E2',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".12"><ellipse cx="200" cy="330" rx="210" ry="110"/><ellipse cx="195" cy="600" rx="200" ry="60"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><circle cx="70" cy="204" r="4"/><circle cx="200" cy="200" r="4"/><circle cx="330" cy="204" r="4"/></g>`,
      stations: [
        { kind: 'toprope', label: '顶绳', kit: 'climb', clip: 'climb', n: 4, path: 'vert', cols: [132, 177, 222, 267].map(x => ({ x, y0: 300, y1: 432 })), speed: 9, scale: .19, rope: 200 },
        { kind: 'boulder', label: '抱石', kit: 'climb', clip: 'climb', n: 2, path: 'vert', cols: [{ x: 322, y0: 380, y1: 436 }, { x: 362, y0: 380, y1: 436 }], speed: 7, scale: .19 },
        { kind: 'chalk', label: '擦镁粉', kit: 'climb', clip: 'warmup', n: 2, path: 'still', spots: [[150, 540], [240, 540]], chalk: true },
      ],
      sports: { climb: ['toprope', 'boulder', 'chalk'] },
    };
  },
};

// Move a scene's venue up by its lift: background, lamps, venue fronts and every station coordinate.
// The front zones (seats, finish spot) and me stay where they are.
function liftScene(r) {
  const D = r.lift || 0; if (!D) return r;
  const up = y => y - D;
  r.bg = `<rect width="390" height="844" fill="${r.floor}"/><g transform="translate(0 ${-D})">${r.bg}</g>`;
  r.lamps = `<g transform="translate(0 ${-D})">${r.lamps}</g>`; r.lampsTop = `<g transform="translate(0 ${-D})">${r.lampsTop}</g>`;
  r.fronts = r.fronts.map(f => f.lift ? { y: up(f.y), svg: `<g transform="translate(0 ${-D})">${f.svg}</g>` } : f);
  r.stations = r.stations.map(st => ({ ...st,
    lane: st.lane && { ...st.lane, y: up(st.lane.y) },
    lanes: st.lanes && st.lanes.map(L => ({ ...L, y: up(L.y) })),
    spots: st.spots && st.spots.map(([x, y]) => [x, up(y)]),
    cols: st.cols && st.cols.map(c => ({ ...c, y0: up(c.y0), y1: up(c.y1) })),
    rope: st.rope && up(st.rope),
    barY: st.bar ? up(364) : undefined }));
  return r;
}

