#!/usr/bin/env python3
# The jaws: each body's and hair's head art cut to the chin beside each shoulder, drawn again over
# that arm (rig parts `jawL` and `jawR`). The arms are drawn after the head so a raised hand stays
# in front of the face, which also put every sleeve's shoulder over the chin's outline; the jaw
# tucks the shoulder back under the chin until the arm comes up to the face (the parts' `hides`).
#
# Run `python3 ios/Packages/Avatar/Tools/jaws.py` after changing a head; it rewrites every
# art/body/<variant>/jawL.svg and jawR.svg, and the hair's where its head reaches the chin.
# Needs `pip install shapely svgelements`.
import glob, os
from shapely.geometry import LineString, Polygon, box
from shapely.geometry.polygon import orient
from svgelements import SVG, Close, Color, Move, Path, Shape

PLACEHOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../Sources/AvatarArt/Placeholder')
# Below every open mouth (the lowest reaches 202.8) and out to each sleeve's inner edge, with the
# middle of the chin left to the head, where nothing of the arms reaches at rest.
REGIONS = {'jawL': box(0, 203, 110, 320), 'jawR': box(130, 203, 240, 320)}
# A bichon's fluff hangs over the shoulders already (`chinFrontL`, `chinFrontR`).
SKIP = {'body/bichon'}


def hexa(color):
    return Color(color).hex[:7].upper() if color is not None and color.value is not None else None


def subpaths(element, steps=96):
    out, points, closed = [], None, False
    for segment in Path(element).segments():
        if isinstance(segment, Move):
            if points: out.append((points, closed))
            points, closed = [(segment.end.x, segment.end.y)], False
        elif isinstance(segment, Close):
            closed = True
        else:
            n = 1 if type(segment).__name__ == 'Line' else steps
            points += [(segment.point(i / n).x, segment.point(i / n).y) for i in range(1, n + 1)]
    if points: out.append((points, closed))
    return out


def fmt(points):
    return ' '.join(('M' if k == 0 else 'L') + f' {x:.2f} {y:.2f}' for k, (x, y) in enumerate(points))


def pieces(geometry, kind):
    parts = [geometry] if geometry.geom_type == kind else list(getattr(geometry, 'geoms', []))
    return [g for g in parts if g.geom_type == kind]


def jaw(head, region):
    out, fills = [], []
    for element in SVG.parse(head).elements():
        if not isinstance(element, Shape): continue
        fill, stroke = hexa(element.fill), hexa(element.stroke)
        values = element.values
        for points, closed in subpaths(element):
            if fill and len(points) > 2:
                faded = values.get('fill-opacity') or values.get('opacity')
                extra = ''.join(f' {k}="{values[k]}"' for k in ('fill-opacity', 'opacity') if values.get(k))
                fills.append((len(out), Polygon(points).buffer(0).intersection(region), fill, extra, not faded))
                out.append(None)
            if stroke and element.stroke_width:
                cut = LineString(points + ([points[0]] if closed else [])).intersection(region)
                d = ' '.join(fmt(line.coords) for line in pieces(cut, 'LineString') if line.length > 0.2)
                if d:
                    extra = ''.join(f' {k}="{values[k]}"' for k in
                                    ('stroke-opacity', 'opacity', 'stroke-linecap', 'stroke-linejoin') if values.get(k))
                    out.append(f'<path d="{d}" fill="none" stroke="{stroke}" '
                               f'stroke-width="{round(element.stroke_width, 2)}"{extra}/>')
    # Each fill as it shows, less what opaque fills drawn later cover, so a cut edge never stacks
    # two colours (their antialiasing would leave a hairline of the lower one along the cut).
    for k, (at, shape, fill, extra, _) in enumerate(fills):
        for later in fills[k + 1:]:
            if later[4]: shape = shape.difference(later[1])
        rings = []
        for polygon in pieces(shape, 'Polygon'):
            if polygon.area < 0.05: continue
            polygon = orient(polygon, 1.0)  # holes wind the other way, so the nonzero rule keeps them
            rings += [fmt(list(r.coords)[:-1]) + ' Z' for r in [polygon.exterior, *polygon.interiors]]
        if rings: out[at] = f'<path d="{" ".join(rings)}" fill="{fill}"{extra}/>'
    return [line for line in out if line]


for head in sorted(glob.glob(os.path.join(PLACEHOLDER, 'art', '*', '*', 'head.svg'))):
    folder = os.path.dirname(head)
    slot, variant = folder.split(os.sep)[-2:]
    if slot not in ('body', 'hair'): continue
    for part, region in REGIONS.items():
        target = os.path.join(folder, f'{part}.svg')
        shapes = [] if f'{slot}/{variant}' in SKIP else jaw(head, region)
        if shapes:
            with open(target, 'w') as f:
                f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">\n  ' + '\n  '.join(shapes) + '\n</svg>\n')
        elif os.path.exists(target):
            os.remove(target)
