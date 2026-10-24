// Dresses a look in the app's character art (ios/Packages/Avatar, AvatarArt): one string of SVG
// per rig part, back to front, as the app's player draws it. The site's generator dresses the home
// page's cast with it, and the invite page each member's look as the API sends it.
//
// `wardrobe` is the art as scripts/generate.mjs bundles it: the rig's `parts` and `defaults`, the
// `variants` of each slot, every layer's `art` by "slot/variant/layer" (and "base/layer"), and each
// recolorable variant's `tones` by "slot/variant", and the arm each variant that keeps level hangs
// from (`holds`, from its hold.json). A slot whose variant this art doesn't have wears
// the slot's default, as in the app.

// A shade keeps its relation to the base color: each channel scales by shade/base.
const channels = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
function shadeTo(base, shade, color) {
  const [b, s, c] = [channels(base), channels(shade), channels(color)];
  return (
    '#' +
    c
      .map((n, i) => Math.max(0, Math.min(255, Math.round(n * (s[i] / Math.max(b[i], 1))))))
      .map((n) => n.toString(16).toUpperCase().padStart(2, '0'))
      .join('')
  );
}

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const replaceAllCaseless = (text, from, to) => text.replace(new RegExp(escape(from), 'gi'), to);

/**
 * `variants` picks a variant per slot, `colors` a swatch per slot (through its tones), and
 * `shoes` swaps colors in the shoes by literal find and replace (shoes have no tones).
 */
export function dress(wardrobe, variants, colors = {}, shoes = []) {
  const look = { ...wardrobe.defaults };
  for (const [slot, variant] of Object.entries(variants))
    // Own keys only: a slot named like an Object method ("constructor") is no slot.
    if (Object.hasOwn(wardrobe.variants, slot) && wardrobe.variants[slot].includes(variant))
      look[slot] = variant;
  // Each part's body art, for the hands that layers are held in (a racket's grip).
  const bodies = {};
  const parts = wardrobe.parts.map((part) =>
    (part.layers ?? []).map(({ slot, art: name, hand }) => {
      if (slot === undefined) return { svg: wardrobe.art[`base/${name}`] ?? '' };
      if (!look[slot]) return { svg: '' };
      let svg = wardrobe.art[`${slot}/${look[slot]}/${name}`];
      if (svg === undefined) return { svg: '' };
      if (slot === 'shoes') {
        for (const [from, to] of shoes) svg = svg.replaceAll(from, to);
      } else if (slot in colors) {
        const tones = wardrobe.tones[`${slot}/${look[slot]}`];
        if (tones !== undefined) {
          const color = colors[slot];
          for (const shade of tones.shades ?? [])
            svg = replaceAllCaseless(svg, shade, shadeTo(tones.base, shade, color));
          svg = replaceAllCaseless(svg, tones.base, color);
        }
      }
      if (slot === 'body') bodies[part.id] = svg;
      return { svg, hand };
    }),
  );
  return parts.map((layers) =>
    layers.map(({ svg, hand }) => (hand ? held(svg, wardrobe.skin, bodies[hand]) : svg)).join(''),
  );
}

// A layer held in a hand, drawn in the rig's skin, takes the colors of that hand: the last
// shape of the hand's body art with both a fill and an outline, as in the app.
const attribute = (tag, name) => tag.match(new RegExp(`\\s${name}="(#[0-9A-Fa-f]{6})"`))?.[1];
function held(svg, skin, body) {
  const shapes = [...(body ?? '').matchAll(/<[a-z]+\b[^>]*>/g)]
    .map(([tag]) => [attribute(tag, 'fill'), attribute(tag, 'stroke')])
    .filter(([fill, stroke]) => fill && stroke);
  if (!skin || shapes.length === 0) return svg;
  const [fill, stroke] = shapes[shapes.length - 1];
  return replaceAllCaseless(
    replaceAllCaseless(replaceAllCaseless(svg, skin.stroke, '\u0000'), skin.fill, fill),
    '\u0000',
    stroke,
  );
}

/**
 * The parts of `variants`' look that keep level in a hand, as indices into `wardrobe.parts`: the
 * parts hanging from the arm a worn variant's hold.json names that draw that variant's slot, as
 * the app's `Figure.level` finds them. The site never plays a prop's own move, so they always
 * hang level.
 */
export function leveled(wardrobe, variants) {
  const look = { ...wardrobe.defaults, ...variants };
  for (const slot of Object.keys(look).sort()) {
    const arm = wardrobe.holds?.[`${slot}/${look[slot]}`];
    if (arm === undefined) continue;
    return wardrobe.parts.flatMap((part, i) =>
      part.parent === arm && (part.layers ?? []).some((layer) => layer.slot === slot) ? [i] : [],
    );
  }
  return [];
}
