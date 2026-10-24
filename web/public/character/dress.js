// Dresses a look in the app's character art (ios/Packages/Avatar, AvatarArt): one string of SVG
// per rig part, back to front, as the app's player draws it. The site's generator dresses the home
// page's cast with it, and the invite page each member's look as the API sends it.
//
// `wardrobe` is the art as scripts/generate.mjs bundles it: the rig's `parts` and `defaults`, the
// `variants` of each slot, every layer's `art` by "slot/variant/layer" (and "base/layer"), and each
// recolorable variant's `tones` by "slot/variant". A slot whose variant this art doesn't have wears
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

/** `variants` picks a variant per slot, and `colors` a swatch per slot, through its tones. */
export function dress(wardrobe, variants, colors = {}) {
  const look = { ...wardrobe.defaults };
  for (const [slot, variant] of Object.entries(variants))
    // Own keys only: a slot named like an Object method ("constructor") is no slot.
    if (Object.hasOwn(wardrobe.variants, slot) && wardrobe.variants[slot].includes(variant))
      look[slot] = variant;
  return wardrobe.parts.map((part) =>
    (part.layers ?? [])
      .map(({ slot, art: name }) => {
        if (slot === undefined) return wardrobe.art[`base/${name}`] ?? '';
        if (!look[slot]) return '';
        let svg = wardrobe.art[`${slot}/${look[slot]}/${name}`];
        if (svg === undefined) return '';
        if (slot in colors) {
          const tones = wardrobe.tones[`${slot}/${look[slot]}`];
          if (tones === undefined) return svg;
          const color = colors[slot];
          for (const shade of tones.shades ?? [])
            svg = replaceAllCaseless(svg, shade, shadeTo(tones.base, shade, color));
          svg = replaceAllCaseless(svg, tones.base, color);
        }
        return svg;
      })
      .join(''),
  );
}
