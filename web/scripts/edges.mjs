// The cloth of an arm's art as one shape, for its shoulder (rig.json's `shoulder`): where the arm
// leaves the body near its pivot, the page outlines the arm's own edge, as the app does
// (AvatarUI's FigureDrawing). Worked out here, once per art file, since browsers have no union.
import polygonClipping from 'polygon-clipping';

const STEPS = 12;

// Each subpath of an SVG path as points, its curves in short straight steps.
function subpaths(d) {
  const tokens = d.match(/[MmLlHhVvQqCcZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?/g) ?? [];
  const out = [];
  let points = [];
  let [x, y, sx, sy, i, command] = [0, 0, 0, 0, 0, 'M'];
  const number = () => +tokens[i++];
  const end = (closed) => {
    if (points.length >= 2) out.push({ points, closed });
    points = [];
  };
  while (i < tokens.length) {
    if (/[A-Za-z]/.test(tokens[i])) command = tokens[i++];
    const relative = command === command.toLowerCase();
    const [ox, oy] = relative ? [x, y] : [0, 0];
    switch (command.toUpperCase()) {
      case 'M':
        end(false);
        [x, y] = [ox + number(), oy + number()];
        [sx, sy] = [x, y];
        points.push([x, y]);
        command = relative ? 'l' : 'L';
        break;
      case 'L':
        [x, y] = [ox + number(), oy + number()];
        points.push([x, y]);
        break;
      case 'H':
        x = ox + number();
        points.push([x, y]);
        break;
      case 'V':
        y = oy + number();
        points.push([x, y]);
        break;
      case 'Q': {
        const [cx, cy, ex, ey] = [ox + number(), oy + number(), ox + number(), oy + number()];
        for (let k = 1; k <= STEPS; k++) {
          const [t, u] = [k / STEPS, 1 - k / STEPS];
          points.push([
            u * u * x + 2 * u * t * cx + t * t * ex,
            u * u * y + 2 * u * t * cy + t * t * ey,
          ]);
        }
        [x, y] = [ex, ey];
        break;
      }
      case 'C': {
        const c = [
          ox + number(),
          oy + number(),
          ox + number(),
          oy + number(),
          ox + number(),
          oy + number(),
        ];
        const at = (t, a, b, e, f) =>
          (1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t * t * e + t ** 3 * f;
        for (let k = 1; k <= STEPS; k++)
          points.push([at(k / STEPS, x, c[0], c[2], c[4]), at(k / STEPS, y, c[1], c[3], c[5])]);
        [x, y] = [c[4], c[5]];
        break;
      }
      case 'Z':
        end(true);
        [x, y] = [sx, sy];
        points.push([x, y]);
        break;
      default:
        throw new Error(`unknown path command ${command}`);
    }
  }
  end(false);
  return out;
}

const attribute = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];

const circle = (cx, cy, r) =>
  Array.from({ length: 72 }, (_, k) => [
    cx + r * Math.cos((k / 72) * 2 * Math.PI),
    cy + r * Math.sin((k / 72) * 2 * Math.PI),
  ]);

const ring = (points) => [...points, points[0]];

// A filled shape as polygons, each subpath on its own, as the app unions each shape whole.
function polygons(tag) {
  if (tag.startsWith('<circle'))
    return [[ring(circle(+attribute(tag, 'cx'), +attribute(tag, 'cy'), +attribute(tag, 'r')))]];
  return subpaths(attribute(tag, 'd'))
    .filter(({ points }) => points.length >= 3)
    .map(({ points }) => [ring(points)]);
}

const length = (d) =>
  subpaths(d).reduce((total, { points, closed }) => {
    const all = closed ? ring(points) : points;
    let sum = 0;
    for (let k = 1; k < all.length; k++)
      sum += Math.hypot(all[k][0] - all[k - 1][0], all[k][1] - all[k - 1][1]);
    return total + sum;
  }, 0);

// The art's outline: its longest solid line (AvatarDomain's `Artwork.outline`).
function outline(svg) {
  let best;
  for (const tag of svg.match(/<path\b[^>]*>/g) ?? []) {
    const stroke = attribute(tag, 'stroke');
    if (!stroke || stroke === 'none' || attribute(tag, 'stroke-dasharray')) continue;
    const total = length(attribute(tag, 'd'));
    if (!best || total > best.total)
      best = { total, tag, stroke, width: attribute(tag, 'stroke-width') ?? '1' };
  }
  return best;
}

const format = (n) => String(Math.round(n * 100) / 100);

/**
 * The edge of `svg`'s cloth for a shoulder at `pivot` reaching `radius`: one path of its filled
 * shapes' union, drawn in the art's outline. Undefined when its cloth doesn't reach the shoulder
 * (a bare arm's hand) or it has no outline.
 */
export function edge(svg, pivot, radius) {
  const filled = (svg.match(/<(?:path|circle)\b[^>]*>/g) ?? []).filter((tag) => {
    const fill = attribute(tag, 'fill');
    return fill !== undefined && fill !== 'none';
  });
  const line = outline(svg);
  if (!filled.length || !line) return undefined;
  const cloth = polygonClipping.union(...filled.map(polygons));
  const reach = [[ring(circle(pivot[0], pivot[1], radius))]];
  if (!polygonClipping.intersection(cloth, reach).length) return undefined;
  const d = cloth
    .flatMap((polygon) =>
      polygon.map(
        (r) =>
          `M ${r
            .slice(0, -1)
            .map((p) => p.map(format).join(' '))
            .join(' L ')} Z`,
      ),
    )
    .join(' ');
  return { d, stroke: line.stroke, width: line.width };
}

/**
 * `svg` with its outline marked `data-outline`, for the page to stop it where it lies on the
 * body at the shoulder's top, as the app does.
 */
export function markOutline(svg) {
  const line = outline(svg);
  return line ? svg.replace(line.tag, line.tag.replace('<path', '<path data-outline=""')) : svg;
}
