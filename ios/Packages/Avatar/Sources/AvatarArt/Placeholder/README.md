# Placeholder character

Stand-in art and motion until the character design is decided. The formats are the real thing.

- `rig.json`: the parts, back to front, each with its parent, pivot and art layers. Every part is drawn on the shared 240×320 canvas in its rest pose, so artists export each layer from one artboard.
- `art/base/<art>.svg`: parts every character shares (eyes, mouths, shadow). `art/<slot>/<variant>/<art>.svg`: what a look picks per slot: `body` (species and skin: `peach`, `tan`, `cat`, `bear`), `hair`, `hat`, `top`, `bottom`, `prop`. A variant may skip a part (only the cat draws a `tail`).
- `clips/<persona>/idle.json` and `cheer.json`: each persona's idle loop and check-in cheer, as keyframe tracks per part and channel (`rotation` in degrees clockwise, `x`, `y`, `scaleX`, `scaleY`, `opacity`). A key's `ease` shapes the move into it: `linear`, `hold`, `easeIn`, `easeOut`, `easeInOut`, `backOut` or four cubic-Bézier numbers.
- Personas: `deadpan`, `energetic`, `showoff`, `drama`, `shy`. Every look plays every persona. Adding one is a new `clips/<id>/` folder with both clips, plus a `Persona` constant; the tests then check it binds, loops, lands at rest and stays on the canvas.
- SVG: flat paths, circles, ellipses and rects with hex fills and strokes. No transforms, gradients, filters, text or arcs (outline them).
