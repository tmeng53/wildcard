
// Scene art and layout. Every scene uses the same plan:
// the scene's own stations for people whose sport matches; everyone else anywhere on the open floor; me front-centre.
const f1 = n => (+n).toFixed(1);
const THEMES = {
  track:  { name: '跑道',   sig: '#E65345', shade: '#C23B2E', wash: '#FCEDEB', text: '#B83325', on: '#FFFFFF' },
  pool:   { name: '泳池',   sig: '#079BB8', shade: '#067C93', wash: '#E2F5F9', text: '#066E83', on: '#FFFFFF' },
  gym:    { name: '健身房', sig: '#4A6C8C', shade: '#3B5670', wash: '#EDF0F4', text: '#3E5C78', on: '#FFFFFF' },
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

// A soft flat cloud for the outdoor skies.
const cloud = (x, y, k) => `<g transform="translate(${x} ${y}) scale(${k})" fill="#FFFFFF"><rect x="-34" y="-6" width="68" height="16" rx="8"/><circle cx="-10" cy="-6" r="12"/><circle cx="10" cy="-10" r="15"/></g>`;
// A string of small pennants hanging between two points, alternating two colours.
function bunting(x0, x1, y, sag, a, b) {
  let s = `<path d="M${x0} ${y} Q${(x0 + x1) / 2} ${y + sag * 2} ${x1} ${y}" stroke="#C9CFD8" stroke-width="1.2" fill="none"/>`;
  for (let i = 1, n = Math.round((x1 - x0) / 22); i < n; i++) { const t = i / n, x = x0 + (x1 - x0) * t, yy = y + sag * 4 * t * (1 - t); s += `<path d="M${f1(x - 6)} ${f1(yy)} L${f1(x + 6)} ${f1(yy)} L${f1(x)} ${f1(yy + 11)} Z" fill="${i % 2 ? a : b}"/>`; }
  return s;
}

const SCENES = {
  track() {
    let s = `<rect width="390" height="844" fill="#EAF2F7"/>`;
    // back: pennants over the stands, seen full screen when the scene is unboxed; the stands across the whole width
    s += bunting(0, 390, 146, 8, '#E65345', '#FFFFFF');
    s += steps(170, 5, 21, '#FFFFFF', '#DFE7EE');
    s += `<rect x="0" y="275" width="390" height="20" fill="#D5E4C2"/>`;
    s += softHurdle(60, 293, '#FFFFFF') + softHurdle(330, 293, '#FFFFFF');
    // track lanes, flat bands across the screen; the runners use lanes 2 to 4
    s += `<rect x="0" y="295" width="390" height="255" fill="#E65345"/>`;
    [295, 346, 397, 448, 499, 550].forEach(y => s += `<rect x="0" y="${y - 1}" width="390" height="2.4" fill="#FFFFFF" fill-opacity=".85"/>`);
    [[1, 329], [2, 380], [3, 431], [4, 482], [5, 533]].forEach(([n, y]) => s += `<text x="372" y="${y - 6}" text-anchor="middle" font-family="Barlow Condensed,sans-serif" font-weight="700" font-size="20" fill="#FFFFFF" fill-opacity=".5">${n}</text>`);
    // front apron
    s += tiles(551, 851, '#F3F5F0', '#E4E9DC') + `<rect x="0" y="551" width="390" height="6" fill="#D9E3CC"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#D5DBE4');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 55, x1: 335, y0: 380, y1: 500 }], avoid: [], open: [{ x0: 0, x1: 390, y0: 480, y1: 650 }], lift: 36, floor: '#F3F5F0',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".08"><ellipse cx="110" cy="450" rx="190" ry="80"/><ellipse cx="290" cy="470" rx="190" ry="80"/></g>`,
      lampsTop: `<rect x="186" y="180" width="196" height="3" fill="#FFF3C4"/>`,
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
    // the wall over the pool, seen full screen when the scene is unboxed: a small pace clock and backstroke flags
    s += `<circle cx="60" cy="122" r="18" fill="#FFFFFF" stroke="#067C93" stroke-width="2.4"/><path d="M60 122 V109 M60 122 L69 127" stroke="#E65345" stroke-width="2.2" stroke-linecap="round"/>`;
    s += bunting(0, 390, 157, 4, '#E65345', '#FFFFFF');
    s += tiles(167, 233, '#EEF6F8', '#DCEBEF', 26);
    s += `<rect x="0" y="229" width="390" height="5" fill="#CFE3E9"/>` + tiles(234, 308, '#F7FAFB', '#E6EFF2', 37);
    s += `<g transform="translate(326 23)"><rect x="0" y="214" width="5" height="64" rx="2.5" fill="#FFFFFF"/><rect x="24" y="214" width="5" height="64" rx="2.5" fill="#FFFFFF"/><rect x="-4" y="208" width="37" height="10" rx="5" fill="#E65345"/><rect x="2" y="238" width="25" height="5" rx="2.5" fill="#FFFFFF"/><rect x="2" y="258" width="25" height="5" rx="2.5" fill="#FFFFFF"/></g>`;
    s += `<rect x="0" y="304" width="390" height="5" fill="#CFE3E9"/>`;
    s += `<rect x="0" y="309" width="390" height="167" fill="#5FC0D5"/>`;
    const laneY = [358, 391, 424, 457, 490, 523];
    // the swimmers use the lower four lanes; the top one stays empty
    s += `<rect x="20" y="324" width="350" height="2" fill="#067C93" fill-opacity=".22"/>`;
    for (let i = -1; i < 3; i++) { const y = 374 + i * 33; for (let x = 4; x < 390; x += 9) s += `<circle cx="${x}" cy="${y}" r="2.6" fill="${(x / 9 | 0) % 6 < 2 ? '#E65345' : '#FFFFFF'}"/>`; }
    for (let i = 0; i < 4; i++) s += `<rect x="20" y="${laneY[i] - 1}" width="350" height="2" fill="#067C93" fill-opacity=".22"/>`;
    s += `<rect x="0" y="474" width="390" height="10" fill="#CFE3E9"/>` + tiles(482, 848, '#F7FAFB', '#E6EFF2');
    s += benchBack(Z.leave, '#FFFFFF', '#CFE3E9');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { avoid: [], open: [{ x0: 0, x1: 390, y0: 474, y1: 650 }], lift: 36, floor: '#F7FAFB',
      bg: s, fronts: [],
      lamps: `<g fill="#BFF1FF" fill-opacity=".16"><rect x="0" y="309" width="390" height="167"/></g><g fill="#FFE9A8" fill-opacity=".1"><ellipse cx="90" cy="600" rx="140" ry="50"/><ellipse cx="300" cy="600" rx="140" ry="50"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><circle cx="120" cy="173" r="4"/><circle cx="270" cy="173" r="4"/></g>`,
      water: { y0: 309, y1: 476 },
      stations: [
        { kind: 'swim', label: '自由泳', kit: 'swim', clip: 'swim', n: 4, path: 'lanes', lanes: laneY.slice(0, 4).map(y => lane(36, 354, y + 6)), speed: 34, swim: true },
      ],
      sports: { swim: ['swim'] },
    };
  },
  gym() {
    const G1 = '#2C3540', G2 = '#3E4955', V = '#4A6C8C', V2 = '#A9C2DA';
    let s = `<rect width="390" height="844" fill="#EDF0F4"/>`;
    // the wall above the floor, seen full screen when the scene is unboxed: mirrors, a speaker, and a kettlebell rack under the wall line
    [[150, 120], [276, 120]].forEach(([x, w]) => s += `<rect x="${x - w / 2}" y="60" width="${w}" height="150" rx="6" fill="#E3E8EE" stroke="#CDD6DF" stroke-width="2"/><path d="M${x - w / 2 + 18} 190 L${x - w / 2 + 58} 80 M${x - w / 2 + 38} 190 L${x - w / 2 + 66} 112" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round" opacity=".8"/>`);
    s += `<rect x="40" y="296" width="96" height="4" rx="2" fill="#C3CDD7"/>${[54, 76, 98, 122].map((x, i) => { const r = 6 + Math.min(i, 2), cy = 294 - r; return `<path d="M${x - .6 * r} ${cy - .5 * r} C${x - .6 * r} ${cy - 1.8 * r} ${x + .6 * r} ${cy - 1.8 * r} ${x + .6 * r} ${cy - .5 * r}" stroke="${G1}" stroke-width="2.6" fill="none"/><circle cx="${x}" cy="${cy}" r="${r}" fill="${G1}"/>`; }).join('')}`;
    s += `<rect x="350" y="66" width="22" height="32" rx="4" fill="${G1}"/><circle cx="361" cy="87" r="6" fill="${G2}"/><circle cx="361" cy="74" r="2.5" fill="${V2}"/>`;
    s += `<rect x="0" y="246" width="390" height="6" fill="${V}"/><rect x="0" y="252" width="390" height="3" fill="${V2}"/>`;
    s += tiles(310, 846, '#DBE2E8', '#CCD5DE') + `<rect x="0" y="310" width="390" height="4" fill="#C3CDD7"/>`;
    // dark rubber platforms only under the machines
    s += `<rect x="30" y="384" width="160" height="40" rx="8" fill="#3B5670"/><rect x="206" y="384" width="160" height="40" rx="8" fill="#3B5670"/>`;
    s += `<rect x="40" y="474" width="138" height="5" rx="2.5" fill="#B9C5D1"/>`;
    for (let i = 0; i < 6; i++) s += `<rect x="${46 + i * 22}" y="465" width="6" height="11" rx="2" fill="${G1}"/><rect x="${56 + i * 22}" y="465" width="6" height="11" rx="2" fill="${G1}"/><rect x="${51 + i * 22}" y="469" width="6" height="3" fill="#9AA8B6"/>`;
    // station furniture
    const tread = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-4" width="52" height="10" rx="3" fill="${G2}"/><rect x="-24" y="-3" width="48" height="5" rx="2" fill="#1A1C21"/><rect x="18" y="-40" width="4" height="38" rx="2" fill="#70757F"/><rect x="10" y="-46" width="20" height="9" rx="2" fill="${G2}"/><rect x="13" y="-44" width="9" height="4" fill="${V2}"/></g>`;
    const rack = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="21" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="-30" y="-2" width="60" height="4" rx="2" fill="#1A1C21"/></g>`;
    const mat = x => `<path d="M${x - 28} 516 L${x + 28} 516 L${x + 33} 532 L${x - 33} 532 Z" fill="${V}"/><path d="M${x + 24} 516 L${x + 28} 516 L${x + 33} 532 L${x + 28} 532 Z" fill="${V2}"/>`;
    s += tread(70) + tread(146) + rack(246) + rack(322) + mat(250) + mat(326);
    s += benchBack(Z.leave, '#FFFFFF', '#C3CDD7');
    const bar = x => ({ y: 412.6, svg: `<rect x="${x - 32}" y="364" width="64" height="3" rx="1.5" fill="#9AA8B6"/>` });
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 420, y1: 500 }], avoid: [{ x0: 40, x1: 350, y0: 350, y1: 392 }, { x0: 40, x1: 178, y0: 440, y1: 456 }], open: [{ x0: 0, x1: 390, y0: 440, y1: 650 }], lift: 24, floor: '#DBE2E8',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".1"><ellipse cx="110" cy="440" rx="150" ry="60"/><ellipse cx="290" cy="460" rx="150" ry="60"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><rect x="60" y="180" width="90" height="4" rx="2"/><rect x="240" y="180" width="90" height="4" rx="2"/></g>`,
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
    // the sky over the fence, seen full screen when the scene is unboxed: two clouds
    s += cloud(112, 100, 1) + cloud(292, 70, .75);
    s += `<rect x="0" y="190" width="390" height="114" fill="#E6ECDD"/>`;
    for (let y = 190; y < 304; y += 16) for (let x = 0; x < 390; x += 16) s += `<path d="M${x} ${y} L${x + 16} ${y + 16} M${x + 16} ${y} L${x} ${y + 16}" stroke="#CBD5BB" stroke-width="1.2"/>`;
    // quiet details on the fence: a scoreboard, two balls stuck in the mesh, a ball basket
    const ball = (x, y) => `<circle cx="${x}" cy="${y}" r="3.4" fill="#D6DE5A"/><path d="M${x - 2.4} ${y - 2.4} Q${x + 1} ${y} ${x - 2.4} ${y + 2.4}" stroke="#FFFFFF" stroke-width=".9" fill="none"/>`;
    s += `<rect x="28" y="234" width="72" height="32" rx="6" fill="#5C7A2D"/><rect x="63.5" y="240" width="1" height="20" fill="#FFFFFF" fill-opacity=".3"/>`;
    s += `<g font-family="Barlow Condensed,sans-serif" font-weight="800" font-size="19" fill="#FFFFFF" fill-opacity=".85" text-anchor="middle"><text x="46" y="257">15</text><text x="82" y="257">30</text></g>`;
    s += ball(144, 254) + ball(192, 286);
    s += `<g transform="translate(210 0)"><rect x="114" y="291" width="2" height="13" fill="#3B5119"/><rect x="134" y="291" width="2" height="13" fill="#3B5119"/>${ball(119, 284)}${ball(126, 282)}${ball(132, 285)}<rect x="111" y="286" width="28" height="9" rx="2" fill="none" stroke="#3B5119" stroke-width="1.6"/></g>`;
    // the court: a darker run-off, the court itself a shade lighter with soft mowing stripes, crisp lines and centre marks
    s += `<rect x="0" y="304" width="390" height="256" fill="#5F7F2E"/><rect x="24" y="316" width="342" height="204" fill="#6E8F38"/>`;
    for (let i = 0; i < 6; i++) if (i % 2) s += `<rect x="24" y="${316 + i * 34}" width="342" height="34" fill="#FFFFFF" fill-opacity=".05"/>`;
    s += `<path d="M24 316 H366 V520 H24 Z M54 316 V520 M336 316 V520 M54 376 H336 M54 460 H336 M195 376 V460 M195 316 V323 M195 520 V513" stroke="#FFFFFF" stroke-width="2.4" fill="none"/>`;
    s += tiles(560, 850, '#F0F3E9', '#E0E7D3') + `<rect x="0" y="556" width="390" height="6" fill="#5C7A2D"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#C9D3BB');
    const net = { lift: true, y: 418.5, svg: `<rect x="18" y="402" width="354" height="16" fill="#FFFFFF" fill-opacity=".28"/><path d="M18 402 H372" stroke="#FFFFFF" stroke-width="3"/>${Array.from({ length: 30 }, (_, i) => `<rect x="${20 + i * 12}" y="403" width="1" height="15" fill="#FFFFFF" fill-opacity=".5"/>`).join('')}<rect x="16" y="398" width="4" height="22" fill="#3B5119"/><rect x="370" y="398" width="4" height="22" fill="#3B5119"/>` };
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 70, x1: 330, y0: 346, y1: 470, avoid: [{ x0: 0, x1: 390, y0: 375, y1: 402 }] }], avoid: [], open: [{ x0: 0, x1: 390, y0: 480, y1: 650 }], lift: 30, floor: '#F0F3E9',
      bg: s, fronts: [net],
      lamps: `<g fill="#FFE9A8" fill-opacity=".13"><ellipse cx="195" cy="450" rx="230" ry="110"/></g>`,
      lampsTop: `<g fill="#FFF3C4"><rect x="20" y="186" width="40" height="5" rx="2"/><rect x="330" y="186" width="40" height="5" rx="2"/></g><g font-family="Barlow Condensed,sans-serif" font-weight="800" font-size="19" fill="#FFF3C4" text-anchor="middle"><text x="46" y="257">15</text><text x="82" y="257">30</text></g>`,
      stations: [
        { kind: 'rally', label: '对打', kit: 'tennis', keepProp: true, clip: 'tennis', n: 4, path: 'still', spots: [[130, 376], [130, 492], [262, 376], [262, 492]], rally: true },
        { kind: 'serve', label: '发球', kit: 'tennis', keepProp: true, clip: 'tennis', n: 2, path: 'still', spots: [[40, 352], [350, 496]], serve: true },
      ],
      sports: { tennis: ['rally', 'serve'] },
    };
  },
  climb() {
    let s = `<rect width="390" height="844" fill="#EAD8CC"/>`;
    // the hall above the wall, seen full screen when the scene is unboxed: a roof truss with lamps
    s += `<rect x="0" y="28" width="390" height="4" fill="#D8C2B3"/><rect x="0" y="58" width="390" height="4" fill="#D8C2B3"/>`;
    for (let x = 0; x < 390; x += 30) s += `<path d="M${x} 32 L${x + 15} 58 L${x + 30} 32" stroke="#D8C2B3" stroke-width="3" fill="none"/>`;
    [90, 195, 300].forEach(x => s += `<rect x="${x - 1}" y="62" width="2" height="64" fill="#C9AF9E"/><path d="M${x - 14} 138 Q${x} 116 ${x + 14} 138 Z" fill="#8E4A2C"/>`);
    const HZ = 446;
    const P = [['M-10 172 L120 190 L104 330 L-10 312Z', '#F1E5DD'], ['M120 190 L250 166 L268 316 L104 330Z', '#E8D6CA'], ['M250 166 L400 198 L400 334 L268 316Z', '#EFE2D9'],
      [`M-10 312 L104 330 L96 ${HZ} L-10 ${HZ}Z`, '#E5D1C3'], [`M104 330 L268 316 L282 ${HZ} L96 ${HZ}Z`, '#EEDFD5'], [`M268 316 L400 334 L400 ${HZ} L282 ${HZ}Z`, '#E3CEBF']];
    P.forEach(([d, c]) => s += `<path d="${d}" fill="${c}" stroke="#F7EFE9" stroke-width="2"/>`);
    let k = 7; const r = () => (k = (k * 9301 + 49297) % 233280) / 233280;
    const routes = [['#8E4A2C', 132], ['#2B2E36', 177], ['#FFFFFF', 222], ['#C6F432', 267], ['#2D5BA0', 318], ['#E65345', 360]];
    routes.forEach(([c, x]) => { for (let y = 202; y < HZ - 20; y += 24) { const xx = x + (r() - .5) * 22, rr = 3.5 + r() * 3; s += `<ellipse cx="${f1(xx)}" cy="${y}" rx="${f1(rr * 1.3)}" ry="${f1(rr)}" transform="rotate(${f1(r() * 180)} ${f1(xx)} ${y})" fill="${c}" ${c === '#FFFFFF' ? 'stroke="#D9C3B5" stroke-width="1.2"' : ''}/>`; } });
    [132, 177, 222, 267].forEach(x => s += `<circle cx="${x}" cy="176" r="3" fill="#6F3820"/>`);
    s += `<rect x="0" y="${HZ - 6}" width="390" height="6" fill="#6F3820"/>` + tiles(HZ, HZ + 400, '#F2E9E2', '#E4D6CB');
    s += `<rect x="0" y="${HZ}" width="390" height="34" fill="#8E4A2C"/>${[100, 290].map(x => `<rect x="${x}" y="${HZ}" width="2" height="34" fill="#6F3820"/>`).join('')}<rect x="0" y="${HZ + 30}" width="390" height="4" fill="#6F3820"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#E0CFC2');
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 482, y1: 482 }], avoid: [], open: [{ x0: 0, x1: 390, y0: 470, y1: 650 }], lift: 10, floor: '#F2E9E2',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".12"><ellipse cx="200" cy="330" rx="210" ry="110"/><ellipse cx="195" cy="600" rx="200" ry="60"/></g>`,
      lampsTop: `<g fill="#FFF3C4">${[90, 195, 300].map(x => `<rect x="${x - 10}" y="137" width="20" height="3" rx="1.5"/>`).join('')}<circle cx="70" cy="180" r="4"/><circle cx="200" cy="176" r="4"/><circle cx="330" cy="180" r="4"/></g>`,
      stations: [
        { kind: 'toprope', label: '顶绳', kit: 'climb', clip: 'climb', n: 4, path: 'vert', cols: [132, 177, 222, 267].map(x => ({ x, y0: 300, y1: 432 })), speed: 9, scale: .19, rope: 176 },
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


// Draft: the 雪场 scene, in the same plan and helpers as ios/Packages/CheckIn/SceneArt/scenes.js
// (this file is appended after that one's helpers). A glacier peak fills the view: skiers carve
// across its face; everyone else stands on the smooth snow below, as on the other scenes.
THEMES.ski = { name: '雪场', sig: '#16384D', shade: '#0E2636', wash: '#EAF7FD', text: '#16384D', on: '#D6F1FB' };
SCENES.ski = function () {
  const SKY = '#DCEAF6', FAR = '#C3D9EC', SNOW = '#FFFFFF', SHADE = '#E3EDF6', ICE1 = '#C9DFF0', ICE2 = '#A9CAE6', ICE3 = '#8DB6DB', BASE = '#F6F9FC', DRIFT = '#EAF1F8';
  let s = `<rect width="390" height="844" fill="${SKY}"/>`;
  // a pale sun and two clouds high up, seen full screen when the scene is unboxed
  s += `<circle cx="318" cy="70" r="22" fill="#FFF7E0"/>` + cloud(80, 66, .8) + cloud(250, 120, .6);
  // far range, faint, then a nearer range, each topped with snow
  s += `<path d="M-10 300 L30 214 L66 250 L104 196 L140 238 L170 214 L210 300 Z M200 300 L262 210 L296 244 L330 190 L372 236 L400 222 L400 300 Z" fill="#CFE0EF"/>`;
  s += `<path d="M30 214 L22 230 L32 226 L40 232 L46 224 Z M104 196 L92 216 L104 211 L114 218 L122 210 Z M330 190 L316 212 L330 206 L340 213 L350 204 Z M262 210 L252 226 L262 222 L270 228 Z" fill="${SNOW}"/>`;
  s += `<path d="M-10 330 L34 262 L58 284 L84 254 L120 330 Z M290 330 L328 258 L352 280 L372 262 L400 290 L400 330 Z" fill="#B7CFE5"/>`;
  s += `<path d="M34 262 L26 276 L36 272 L44 278 Z M84 254 L74 270 L86 266 L94 272 Z M328 258 L318 274 L330 269 L338 275 Z" fill="${SNOW}"/>`;
  // the glacier peak, cut in planes: sunlit planes on the left, shaded and ice planes on the right
  const AX = 200, AY = 96;
  s += `<path d="M${AX} ${AY} L-60 560 L262 560 L278 450 L236 372 L252 300 L214 232 L232 170 Z" fill="${SNOW}"/>`;
  s += `<path d="M${AX} ${AY} L150 230 L176 300 L120 380 L150 470 L90 560 L-60 560 Z" fill="#F3F7FB"/>`;
  s += `<path d="M${AX} ${AY} L232 170 L214 232 L252 300 L236 372 L278 450 L262 560 L460 560 Z" fill="${SHADE}"/>`;
  s += `<path d="M232 170 L300 250 L252 300 L214 232 Z M278 450 L350 430 L420 560 L262 560 Z" fill="#D2E2F0"/>`;
  // blue ice where the snow has blown off, with a white edge where light catches it
  s += `<path d="M232 170 L268 206 L244 238 Z M252 300 L304 326 L282 364 L262 350 Z M330 360 L376 400 L350 414 Z M278 450 L330 470 L304 506 Z" fill="${ICE1}"/>`;
  s += `<path d="M268 206 L294 246 L244 238 Z M304 326 L326 372 L282 364 Z M330 470 L352 514 L304 506 Z M376 400 L398 440 L350 414 Z" fill="${ICE2}"/>`;
  s += `<path d="M232 170 L268 206 M252 300 L304 326 M278 450 L330 470 M330 360 L376 400" stroke="${SNOW}" stroke-width="2" stroke-linecap="round"/>`;
  s += `<path d="M300 268 l14 -4 M318 296 l12 -5 M356 446 l14 -5 M294 414 l12 -3 M340 330 l10 -3" stroke="${ICE3}" stroke-width="2.4" stroke-linecap="round"/>`;
  // snow on the ridge and a cornice along it
  s += `<path d="M${AX} ${AY} L214 120 L206 128 L222 146 L210 150 Z" fill="${SNOW}"/><path d="M${AX} ${AY} L232 170 L214 232 L252 300 L236 372 L278 450 L262 560" fill="none" stroke="${SNOW}" stroke-width="3" stroke-linejoin="round"/>`;
  // ski tracks curving down the sunlit face
  s += `<path d="M150 300 Q 90 330 140 360 T 120 430 T 170 500 T 140 556" fill="none" stroke="#E2ECF5" stroke-width="2" stroke-linecap="round"/><path d="M158 300 Q 98 330 148 360 T 128 430 T 178 500 T 148 556" fill="none" stroke="#E2ECF5" stroke-width="2" stroke-linecap="round"/>`;
  s += `<path d="M60 330 Q 20 380 70 420 T 40 520" fill="none" stroke="#E2ECF5" stroke-width="2" stroke-linecap="round"/>`;
  // slalom gates down the run
  const gate = (x, y, c) => `<rect x="${x - 1.6}" y="${y - 28}" width="3.2" height="30" rx="1.6" fill="${c}"/><path d="M${x + 1.6} ${y - 27} L${x + 14} ${y - 22.5} L${x + 1.6} ${y - 17} Z" fill="${c}"/>`;
  s += gate(34, 352, '#E65345') + gate(352, 404, '#2F6FB0') + gate(30, 470, '#E65345') + gate(356, 520, '#2F6FB0');
  // the glacier's foot: a band of blue ice blocks where the run meets the snowfield
  s += `<path d="M-10 548 L30 536 L58 548 L96 532 L132 546 L170 534 L204 548 L246 532 L282 546 L322 534 L356 548 L400 536 L400 572 L-10 572 Z" fill="${ICE1}"/>`;
  s += `<path d="M30 536 L44 572 L-10 572 L-10 548 Z M96 532 L114 572 L76 572 Z M170 534 L190 572 L150 572 Z M246 532 L266 572 L226 572 Z M322 534 L340 572 L302 572 Z" fill="${ICE2}"/>`;
  s += `<path d="M-10 548 L30 536 L58 548 L96 532 L132 546 L170 534 L204 548 L246 532 L282 546 L322 534 L356 548 L400 536 L400 544 L356 556 L322 542 L282 554 L246 540 L204 556 L170 542 L132 554 L96 540 L58 556 L30 544 L-10 556 Z" fill="${SNOW}"/>`;
  // the snowfield: smooth snow and soft drifts, no floor tiles
  s += `<path d="M-10 566 Q 100 554 200 566 Q 300 578 400 562 L400 852 L-10 852 Z" fill="${BASE}"/>`;
  s += `<path d="M-10 660 Q 70 626 170 650 Q 210 660 230 652 L230 668 Q 120 676 -10 690 Z" fill="${DRIFT}"/>`;
  s += `<path d="M400 720 Q 330 690 250 712 Q 220 720 196 716 L196 732 Q 300 740 400 752 Z" fill="${DRIFT}"/>`;
  s += `<path d="M-10 772 Q 120 736 260 760 Q 330 772 400 756 L400 852 L-10 852 Z" fill="#E6EFF8"/><path d="M-10 790 Q 140 760 400 784" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>`;
  const glint = (x, y, r) => `<path d="M${x} ${y - r} L${x + r * .3} ${y - r * .3} L${x + r} ${y} L${x + r * .3} ${y + r * .3} L${x} ${y + r} L${x - r * .3} ${y + r * .3} L${x - r} ${y} L${x - r * .3} ${y - r * .3} Z" fill="${ICE2}"/>`;
  s += glint(34, 600, 4) + glint(240, 590, 3) + glint(150, 700, 3.5) + glint(330, 660, 4) + glint(60, 760, 3);
  const pine = (x, y, k) => `<g transform="translate(${x} ${y}) scale(${k})"><rect x="-2.5" y="-4" width="5" height="10" fill="#7A6656"/><path d="M0 -50 L18 -18 L9 -18 L22 0 L-22 0 L-9 -18 L-18 -18 Z" fill="#3F6A62"/><path d="M0 -50 L18 -18 L9 -18 L22 0 L0 0 Z" fill="#335A53"/><path d="M0 -50 L8 -36 L2 -34 L-3 -37 L-8 -35 Z M-9 -18 L-2 -21 L4 -18 L9 -20 L12 -16 L-14 -16 Z" fill="${SNOW}"/></g>`;
  s += pine(18, 590, .8) + pine(40, 600, .6) + pine(376, 640, .7);
  const snowman = `<g transform="translate(340 612)"><ellipse cx="0" cy="2" rx="22" ry="5" fill="${ICE1}" fill-opacity=".7"/><circle cx="0" cy="-14" r="17" fill="${SNOW}" stroke="${ICE1}" stroke-width="2"/><circle cx="0" cy="-40" r="12" fill="${SNOW}" stroke="${ICE1}" stroke-width="2"/><path d="M-12 -30 Q0 -26 12 -30 L12 -25 Q0 -21 -12 -25 Z" fill="#E65345"/><circle cx="-4" cy="-43" r="1.6" fill="#1F2128"/><circle cx="4" cy="-43" r="1.6" fill="#1F2128"/><path d="M0 -39 L9 -37.5 L0 -36.4 Z" fill="#E8A23A"/><circle cx="0" cy="-16" r="1.8" fill="#1F2128"/><circle cx="0" cy="-8" r="1.8" fill="#1F2128"/></g>`;
  s += snowman;
  s += benchBack(Z.leave, '#FFFFFF', '#D5DBE4');
  return { avoid: [{ x0: 310, x1: 390, y0: 576, y1: 650 }], open: [{ x0: 0, x1: 390, y0: 576, y1: 650 }], lift: 0, floor: BASE,
    bg: s, fronts: [],
    // night: the peak under moonlight, stars over it, a soft glow on the run and the snowfield
    // night: a pool of light on each gate, the gates lit, stars over the peak
    // night: warm light washed over the run and its gates and over the snowfield, as on the other scenes; the gates stay lit
    lamps: `<g fill="#FFE9A8" fill-opacity=".13"><ellipse cx="110" cy="420" rx="170" ry="90"/><ellipse cx="300" cy="470" rx="170" ry="90"/></g><g fill="#FFE9A8" fill-opacity=".1"><ellipse cx="195" cy="640" rx="240" ry="70"/></g>`,
    lampsTop: `<rect x="32.4" y="324" width="3.2" height="30" rx="1.6" fill="#E65345"/><path d="M35.6 325 L48 329.5 L35.6 335 Z" fill="#E65345"/><rect x="350.4" y="376" width="3.2" height="30" rx="1.6" fill="#2F6FB0"/><path d="M353.6 377 L366 381.5 L353.6 387 Z" fill="#2F6FB0"/><rect x="28.4" y="442" width="3.2" height="30" rx="1.6" fill="#E65345"/><path d="M31.6 443 L44 447.5 L31.6 453 Z" fill="#E65345"/><rect x="354.4" y="492" width="3.2" height="30" rx="1.6" fill="#2F6FB0"/><path d="M357.6 493 L370 497.5 L357.6 503 Z" fill="#2F6FB0"/>`,
    stations: [
      { kind: 'carve', label: '滑雪', kit: 'ski', clip: 'skis', n: 2, path: 'carve', lane: lane(-30, 420, 390), speed: 46 },
      { kind: 'carve', label: '滑雪', kit: 'ski', clip: 'skis', n: 2, path: 'carve', lane: lane(-30, 420, 476), speed: 40, dir: -1 },
    ],
    sports: { ski: ['carve'] },
  };
};
