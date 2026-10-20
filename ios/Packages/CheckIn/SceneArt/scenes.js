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
const depthK = y => .17 + (.25 - .17) * Math.min(1, Math.max(0, (y - 280) / (640 - 280)));
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

const SCENES = {
  track() {
    let s = `<rect width="390" height="844" fill="#EAF2F7"/>`;
    // back: stands across the whole width
    s += `<rect x="0" y="200" width="390" height="124" fill="#E1E8EF"/>`;
    for (let r = 0; r < 4; r++) for (let i = 0; i < 34; i++) { const x = 8 + i * 11.5 - (r % 2) * 5, y = 212 + r * 12; s += `<rect x="${x}" y="${y}" width="8" height="6.5" rx="1.6" fill="${(i * 7 + r * 3) % 9 ? '#CBD6E1' : '#FFFFFF'}"/>`; }
    s += `<rect x="0" y="324" width="390" height="22" fill="#C9E0AE"/><path d="M0 330 H390 M0 338 H390" stroke="#BCD89C" stroke-width="2.5"/>`;
    // track lanes, flat bands across the screen
    s += `<rect x="0" y="346" width="390" height="204" fill="#E65345"/>`;
    [346, 397, 448, 499, 550].forEach(y => s += `<rect x="0" y="${y - 1}" width="390" height="2.4" fill="#FFFFFF" fill-opacity=".85"/>`);
    [[1, 380], [2, 431], [3, 482], [4, 533]].forEach(([n, y]) => s += `<text x="370" y="${y - 8}" text-anchor="middle" font-family="Barlow Condensed,sans-serif" font-weight="700" font-size="22" fill="#FFFFFF" fill-opacity=".55">${n}</text>`);
    s += `<rect x="64" y="499" width="4" height="51" fill="#FFFFFF" fill-opacity=".85"/>`;
    // front apron
    s += `<rect x="0" y="551" width="390" height="300" fill="#EEF2E6"/><rect x="0" y="551" width="390" height="6" fill="#D9E3CC"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#D5DBE4');
    const hurdle = x => `<g transform="translate(${x} 389)"><rect x="-15" y="-15" width="3" height="15" fill="#E9EDF2"/><rect x="12" y="-15" width="3" height="15" fill="#E9EDF2"/><rect x="-17" y="-18" width="34" height="6" rx="1.5" fill="#FFFFFF"/><rect x="-9" y="-18" width="6" height="6" fill="#1F2128"/><rect x="5" y="-18" width="6" height="6" fill="#1F2128"/></g>`;
    s += hurdle(130) + hurdle(270);
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 55, x1: 335, y0: 350, y1: 470 }], avoid: [], open: [{ x0: 0, x1: 390, y0: 448, y1: 478 }, { x0: 0, x1: 390, y0: 506, y1: 650 }], lift: 70, floor: '#EEF2E6',
      bg: s, fronts: [],
      lamps: `<g fill="#FFE9A8" fill-opacity=".08"><ellipse cx="110" cy="450" rx="190" ry="80"/><ellipse cx="290" cy="470" rx="190" ry="80"/></g>`,
      lampsTop: `<rect x="186" y="210" width="196" height="3" fill="#FFF3C4"/>`,
      stations: [
        { kind: 'hurdle', label: '跨栏', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 390), speed: 62, hurdles: [130, 270] },
        { kind: 'jog', label: '慢跑', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 441), speed: 48 },
        { kind: 'jog', label: '慢跑', kit: 'run', clip: 'run', n: 2, path: 'loop', lane: lane(-30, 420, 492), speed: 48, dir: -1 },
      ],
      sports: { run: ['jog', 'hurdle'] },
    };
  },
  pool() {
    let s = `<rect width="390" height="844" fill="#E2F5F9"/>`;
    s += `<rect x="0" y="200" width="390" height="66" fill="#EEF6F8"/>`;
    for (let x = 0; x < 390; x += 26) s += `<rect x="${x}" y="200" width="1" height="66" fill="#DCEBEF"/>`;
    for (let y = 212; y < 266; y += 26) s += `<rect x="0" y="${y}" width="390" height="1" fill="#DCEBEF"/>`;
    s += `<rect x="0" y="262" width="390" height="5" fill="#CFE3E9"/><rect x="0" y="267" width="390" height="74" fill="#F7FAFB"/>`;
    for (let x = 0; x < 390; x += 30) s += `<rect x="${x}" y="267" width="1" height="74" fill="#E6EFF2"/>`;
    // lifeguard chair behind the seats
    s += `<rect x="372" y="216" width="3" height="60" fill="#FFFFFF"/><rect x="386" y="216" width="3" height="60" fill="#FFFFFF"/><rect x="368" y="212" width="24" height="7" rx="3" fill="#E65345"/><rect x="372" y="236" width="17" height="3" fill="#FFFFFF"/><rect x="372" y="256" width="17" height="3" fill="#FFFFFF"/>`;
    s += `<rect x="0" y="337" width="390" height="5" fill="#CFE3E9"/>`;
    s += `<rect x="0" y="342" width="390" height="134" fill="#5FC0D5"/>`;
    const laneY = [358, 391, 424, 457, 490, 523];
    for (let i = 0; i < 3; i++) { const y = 374 + i * 33; for (let x = 4; x < 390; x += 9) s += `<circle cx="${x}" cy="${y}" r="2.6" fill="${(x / 9 | 0) % 6 < 2 ? '#E65345' : '#FFFFFF'}"/>`; }
    for (let i = 0; i < 4; i++) s += `<rect x="20" y="${laneY[i] - 1}" width="350" height="2" fill="#067C93" fill-opacity=".22"/>`;
    s += `<path d="M30 400 q10 -4 20 0 M250 450 q10 -4 20 0" stroke="#FFFFFF" stroke-opacity=".5" stroke-width="2" fill="none" stroke-linecap="round"/>`;
    s += `<rect x="0" y="474" width="390" height="10" fill="#CFE3E9"/><rect x="0" y="482" width="390" height="366" fill="#F7FAFB"/>`;
    for (let x = 0; x < 390; x += 30) s += `<rect x="${x}" y="482" width="1" height="366" fill="#E6EFF2"/>`;
    // parasol behind the leave loungers, towel rack behind finish spot
    s += `<rect x="86" y="520" width="3" height="70" fill="#9AA6AD"/><path d="M30 532 Q87 488 144 532 Z" fill="#079BB8"/><path d="M58 532 Q87 494 116 532 Z" fill="#FFFFFF" fill-opacity=".9"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#CFE3E9');
    s += `<rect x="332" y="560" width="3" height="32" fill="#9AA6AD"/><rect x="368" y="560" width="3" height="32" fill="#9AA6AD"/><rect x="330" y="560" width="43" height="3" fill="#9AA6AD"/><rect x="336" y="563" width="12" height="20" rx="2" fill="#F6B92B"/><rect x="352" y="563" width="12" height="16" rx="2" fill="#E65345"/>`;
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 250, y1: 250 }], avoid: [{ x0: 330, x1: 373, y0: 490, y1: 522 }, { x0: 80, x1: 92, y0: 450, y1: 520 }], open: [{ x0: 0, x1: 390, y0: 232, y1: 262 }, { x0: 0, x1: 390, y0: 440, y1: 650 }], lift: 70, floor: '#F7FAFB',
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
    s += `<rect x="0" y="220" width="390" height="4" fill="#1F2128"/><rect x="0" y="224" width="390" height="3" fill="${V}"/>`;
    s += ``;
    s += `<rect x="84" y="246" width="96" height="30" rx="4" fill="#FFFFFF"/><rect x="84" y="246" width="96" height="6" rx="3" fill="${G1}"/><text x="132" y="268" text-anchor="middle" font-family="Barlow Condensed,sans-serif" font-weight="700" font-size="12" fill="${G1}" letter-spacing="1">FRONT DESK</text>`;
    s += `<circle cx="196" cy="240" r="9" fill="#FFFFFF" stroke="${G1}" stroke-width="2"/><path d="M196 240 V234 M196 240 L200 242" stroke="${G1}" stroke-width="1.6" stroke-linecap="round"/>`;
    s += `<rect x="0" y="276" width="390" height="570" fill="#2B2E36"/><rect x="0" y="276" width="390" height="4" fill="#DCDFE4"/>`;
    for (let k = 1; k < 12; k++) s += `<rect x="0" y="${276 + k * k * 4.6}" width="390" height="1" fill="#FFFFFF" fill-opacity=".05"/>`;
    // station furniture
    const tread = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-4" width="52" height="10" rx="3" fill="${G2}"/><rect x="-24" y="-3" width="48" height="5" rx="2" fill="#1A1C21"/><rect x="18" y="-40" width="4" height="38" rx="2" fill="#70757F"/><rect x="10" y="-46" width="20" height="9" rx="2" fill="${G2}"/><rect x="13" y="-44" width="9" height="4" fill="${V}"/></g>`;
    const rack = x => `<g transform="translate(${x} 412)"><rect x="-26" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="21" y="-60" width="5" height="62" fill="#4A4E58"/><rect x="-30" y="-2" width="60" height="4" rx="2" fill="#1A1C21"/></g>`;
    const mat = x => `<path d="M${x - 28} 516 L${x + 28} 516 L${x + 33} 532 L${x - 33} 532 Z" fill="#4A4E58"/><path d="M${x + 24} 516 L${x + 28} 516 L${x + 33} 532 L${x + 28} 532 Z" fill="${V}"/>`;
    s += tread(70) + tread(146) + rack(246) + rack(322) + mat(250) + mat(326);
    s += `<rect x="40" y="474" width="138" height="4" rx="2" fill="#4A4E58"/>`; // dumbbell shelf
    for (let i = 0; i < 6; i++) s += `<rect x="${46 + i * 22}" y="466" width="5" height="10" rx="1.5" fill="#1A1C21"/><rect x="${55 + i * 22}" y="466" width="5" height="10" rx="1.5" fill="#1A1C21"/><rect x="${50 + i * 22}" y="470" width="6" height="2" fill="#A3A8B2"/>`;
    // sofa behind leave, mirror behind finish
    s += `<rect x="6" y="566" width="162" height="22" rx="8" fill="#5B6170"/>`;
    s += benchBack(Z.leave, '#6A7080', '#4A4F5C');
    s += `<rect x="236" y="540" width="134" height="44" rx="4" fill="#9EA6B4"/><rect x="240" y="544" width="126" height="36" rx="2" fill="#C8CED8"/><path d="M260 548 L280 576 M300 548 L316 572" stroke="#FFFFFF" stroke-opacity=".5" stroke-width="3"/>`;
    const bar = x => ({ y: 412.6, svg: `<rect x="${x - 32}" y="364" width="64" height="3" rx="1.5" fill="#A3A8B2"/>` });
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 420, y1: 500 }], avoid: [{ x0: 236, x1: 370, y0: 516, y1: 560 }, { x0: 6, x1: 168, y0: 542, y1: 564 }, { x0: 40, x1: 350, y0: 350, y1: 392 }, { x0: 40, x1: 178, y0: 440, y1: 456 }], open: [{ x0: 0, x1: 390, y0: 300, y1: 650 }], lift: 24, floor: '#2B2E36',
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
    s += `<rect x="0" y="210" width="390" height="114" fill="#E3EAD8"/>`;
    for (let x = 0; x < 390; x += 12) s += `<path d="M${x} 210 L${x + 12} 240 M${x + 12} 210 L${x} 240" stroke="#C9D4B8" stroke-width="1"/>`;
    s += `<rect x="0" y="238" width="390" height="3" fill="#B8C5A3"/>`;
    for (let r = 0; r < 3; r++) s += `<rect x="190" y="${244 + r * 18}" width="196" height="8" rx="2" fill="${r % 2 ? '#CBD5BC' : '#D9E1CC'}"/>`;
    s += `<rect x="0" y="324" width="390" height="236" fill="#6E8F38"/>`;
    s += `<path d="M24 336 H366 V500 H24 Z M54 336 V500 M336 336 V500 M54 376 H336 M54 460 H336 M195 376 V460" stroke="#FFFFFF" stroke-width="2.4" fill="none"/>`;
    s += `<rect x="0" y="560" width="390" height="290" fill="#E9EFDC"/><rect x="0" y="556" width="390" height="6" fill="#5C7A2D"/>`;
    s += `<rect x="40" y="522" width="3" height="70" fill="#9AA6AD"/><path d="M-10 540 Q41 496 92 540 Z" fill="#4F6B22"/><path d="M14 540 Q41 504 68 540 Z" fill="#FFFFFF" fill-opacity=".9"/>`;
    s += benchBack(Z.leave, '#FFFFFF', '#C9D3BB');
    s += `<g transform="translate(352 578)"><rect x="-22" y="-8" width="44" height="18" rx="9" fill="#1F2128"/><circle cx="-8" cy="-10" r="5" fill="#D7F34A"/><circle cx="2" cy="-12" r="5" fill="#D7F34A"/><rect x="14" y="-26" width="8" height="18" rx="3" fill="#079BB8"/></g>`;
    const net = { lift: true, y: 418.5, svg: `<rect x="18" y="402" width="354" height="16" fill="#FFFFFF" fill-opacity=".28"/><path d="M18 402 H372" stroke="#FFFFFF" stroke-width="3"/>${Array.from({ length: 30 }, (_, i) => `<rect x="${20 + i * 12}" y="403" width="1" height="15" fill="#FFFFFF" fill-opacity=".5"/>`).join('')}<rect x="16" y="398" width="4" height="22" fill="#3B5119"/><rect x="370" y="398" width="4" height="22" fill="#3B5119"/>` };
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 70, x1: 330, y0: 316, y1: 440, avoid: [{ x0: 0, x1: 390, y0: 345, y1: 372 }] }], avoid: [{ x0: 328, x1: 376, y0: 492, y1: 530 }, { x0: 34, x1: 46, y0: 462, y1: 532 }], open: [{ x0: 0, x1: 390, y0: 462, y1: 650 }], lift: 60, floor: '#E9EFDC',
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
    s += `<rect x="0" y="${HZ - 6}" width="390" height="6" fill="#6F3820"/><rect x="0" y="${HZ}" width="390" height="400" fill="#9A5534"/>`;
    [560, 700].forEach(y => s += `<rect x="0" y="${y}" width="390" height="2" fill="#7A3E24"/>`);
    [100, 290].forEach(x => s += `<rect x="${x}" y="${HZ}" width="2" height="400" fill="#7A3E24"/>`);
    s += benchBack(Z.leave, '#2B2E36', '#1A1C21');
    s += `<g transform="translate(352 574)"><path d="M-14 0 L14 0 L11 22 L-11 22Z" fill="#FFFFFF"/><rect x="-16" y="-4" width="32" height="6" rx="2" fill="#6F3820"/><rect x="18" y="-6" width="8" height="26" rx="3" fill="#079BB8"/></g>`;
    // open: where anyone not on a station may stand; avoid: props on that floor nobody stands on, in screen coordinates after the lift (never on walls, in water or on the court).
    return { field: [{ x0: 75, x1: 315, y0: 452, y1: 452 }], avoid: [{ x0: 336, x1: 380, y0: 528, y1: 560 }], open: [{ x0: 0, x1: 390, y0: 432, y1: 650 }], lift: 40, floor: '#9A5534',
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
