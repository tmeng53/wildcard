#!/usr/bin/env node
// Drafts each move's `front` keys: which of the two copies of each arm shows, the one behind the
// body (the rest) or the one in front of it, both under the head. Like Spine's draw-order keys, the depth is part
// of the move and held, never inferred from the angle while it plays; this script only writes a
// first draft from where each hand goes, which is then checked frame by frame in the web player and
// corrected by hand in the move's JSON.
//
// An arm is in front while its hand is over the chest, so the hand is drawn over the top rather than
// lost behind it; anywhere else (hanging, on the hip, out to the side, raised beside the head) it
// stays behind, so its sleeve root stays under the top and what is worn over it.
// Only the forearm is drawn in front (Figure.forearm), so after the draft each swap is moved to a
// moment the forearm is clear of the body, where it can't be seen; the tests check every swap.
//
//   node ios/Packages/Avatar/Tools/arm_depth.mjs [--write] [--only <path fragment>] [--keep]
//
// Without --write it prints what it would key. --keep leaves moves that already key `front` as they
// are (hand corrections), which is what to run after adding a new move.
import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const placeholder = join(here, "../Sources/AvatarArt/Placeholder");
const player = join(here, "../../../../web/public/home/avatar.js");
const args = process.argv.slice(2);
const write = args.includes("--write");
const keep = args.includes("--keep");
const only = args.includes("--only") ? args[args.indexOf("--only") + 1] : null;

const rig = JSON.parse(readFileSync(join(placeholder, "rig.json"), "utf8"));
const parts = rig.parts.map(({ id, parent, pivot, opacity, elbow, twin }) => ({
  id,
  parent: parent ?? null,
  pivot,
  opacity: opacity ?? 1,
  ...(elbow ? { elbow } : {}),
  ...(twin ? { twin } : {}),
}));
const window = { WILDCARD_CHARACTERS: { parts } };
vm.runInNewContext(readFileSync(player, "utf8"), {
  window,
  Math,
  Set,
  Object,
  Array,
});
const { pose, layout } = window.WildcardAvatar;
const index = Object.fromEntries(parts.map((p, i) => [p.id, i]));

const apply = ([a, b, c, d, e, f], [x, y]) => [
  a * x + c * y + e,
  b * x + d * y + f,
];
const turn = (deg, [cx, cy]) => {
  const r = (deg * Math.PI) / 180;
  const [c, s] = [Math.cos(r), Math.sin(r)];
  return [c, s, -s, c, cx - c * cx + s * cy, cy - s * cx - c * cy];
};
const multiply = ([a, b, c, d, e, f], [A, B, C, D, E, F]) => [
  a * A + c * B,
  b * A + d * B,
  a * C + c * D,
  b * C + d * D,
  a * E + c * F + e,
  b * E + d * F + f,
];

// Where a hand in front of the body crosses it: over the chest, in rest-pose canvas coordinates.
// The head covers the arms either way, so only the chest decides.
const CHEST = { left: 86, right: 154, top: 200, bottom: 284 };

function inFront(poses, matrices, arm) {
  const part = parts[index[arm]];
  const q = poses[index[arm]];
  const m = q.bend
    ? multiply(matrices[index[arm]], turn(q.bend, part.elbow.at))
    : matrices[index[arm]];
  const hand = apply(m, part.elbow.hand);
  // Each region moves with its part; take the hand back into that part's own coordinates.
  const within = (part, box) => {
    const [a, b, c, d, e, f] = matrices[index[part]];
    const det = a * d - b * c;
    const x = (d * (hand[0] - e) - c * (hand[1] - f)) / det;
    const y = (-b * (hand[0] - e) + a * (hand[1] - f)) / det;
    return x > box.left && x < box.right && y > box.top && y < box.bottom;
  };
  return within("torso", CHEST);
}

const STEP = 1 / 60;
const SHORTEST = 0.12; // a flip shorter than this is noise, not a gesture

export function draft(clip, accent = false) {
  const keyed = {};
  for (const arm of ["armL", "armR"]) {
    const states = [];
    for (let t = 0; t <= clip.duration + 1e-9; t += STEP) {
      const poses = pose(clip, Math.min(t, clip.duration));
      const { matrices } = layout(poses);
      states.push([
        Math.min(t, clip.duration),
        inFront(poses, matrices, arm) ? 1 : 0,
      ]);
    }
    // Runs of the same depth, dropping the ones too short to read.
    let runs = [];
    for (const [t, v] of states) {
      if (runs.length && runs.at(-1).v === v) continue;
      runs.push({ t, v });
    }
    const lengths = runs.map((r, i) => (runs[i + 1]?.t ?? clip.duration) - r.t);
    runs = runs.filter((r, i) => i === 0 || lengths[i] >= SHORTEST);
    runs = runs.filter((r, i) => i === 0 || r.v !== runs[i - 1].v);
    // A one-shot ends at rest, behind, so it hands back to idle as it found it.
    if (!clip.loops && runs.at(-1).v === 1)
      runs.push({ t: clip.duration, v: 0 });
    if (runs.every((r) => r.v === 0)) continue;
    const r3 = (n) => Math.round(n * 1000) / 1000;
    const keys = runs.map((r, i) =>
      i === 0 ? { t: 0, v: r.v } : { t: r3(r.t), v: r.v, ease: "hold" },
    );
    // An accent's tracks start and end at rest at its duration (Clip.accented(by:)).
    if (accent && keys.at(-1).t < clip.duration)
      keys.push({ t: clip.duration, v: 0, ease: "hold" });
    keyed[arm] = keys;
  }
  return keyed;
}

// Where the top-level `tracks` array closes: the offset of its `]`, skipping strings.
function tracksEnd(text) {
  const open = text.indexOf("[", text.indexOf('"tracks"'));
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      for (i++; text[i] !== '"'; i++) if (text[i] === "\\") i++;
    } else if (c === "[" || c === "{") depth++;
    else if ((c === "]" || c === "}") && --depth === 0) return i;
  }
  throw new Error("unclosed tracks");
}

const FRONT_LINE = /^\s*\{"part": "arm[LR]", "channel": "front".*$/;

// The clip's text with its front tracks put back, one a line at the end of the top-level
// `tracks`; the rest of the file keeps its layout.
export function rewrite(text, keyed) {
  const lines = text.split("\n");
  const kept = lines.filter((l) => !FRONT_LINE.test(l)).join("\n");
  const close = tracksEnd(kept);
  const before = kept.slice(0, close).trimEnd().replace(/,$/, "");
  const after = kept.slice(close);
  const lastLine = before.slice(before.lastIndexOf("\n") + 1);
  const closeLine = kept.slice(kept.lastIndexOf("\n", close) + 1, close);
  const closeIndent = /^\s*$/.test(closeLine) ? closeLine : null;
  const indent =
    closeIndent === null
      ? " "
      : closeIndent +
        (lastLine.match(/^\s*/)[0].length > closeIndent.length
          ? lastLine.match(/^\s*/)[0].slice(closeIndent.length)
          : "  ");
  const fronts = Object.entries(keyed).map(
    ([arm, keys]) =>
      `{"part": "${arm}", "channel": "front", "keys": [${keys
        .map(
          (k) =>
            `{"t": ${k.t}, "v": ${k.v}${k.ease ? `, "ease": "${k.ease}"` : ""}}`,
        )
        .join(", ")}]}`,
  );
  if (!fronts.length)
    return `${before}${closeIndent === null ? "" : `\n${closeIndent}`}${after}`;
  const sep = before.endsWith("[") ? "" : ",";
  if (closeIndent === null)
    return `${before}${sep} ${fronts.join(", ")}${after}`;
  return `${before}${sep}\n${fronts.map((f) => indent + f).join(",\n")}\n${closeIndent}${after}`;
}

function* clips(dir) {
  for (const name of readdirSync(dir).sort()) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* clips(path);
    else if (name.endsWith(".json")) {
      const json = JSON.parse(readFileSync(path, "utf8"));
      if (Array.isArray(json.tracks) && typeof json.duration === "number")
        yield [path, json];
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const dir of ["moves", "clips", "accents"]) {
    for (const [path, clip] of clips(join(placeholder, dir))) {
      const name = relative(placeholder, path);
      if (only && !name.includes(only)) continue;
      const hasFront = clip.tracks.some((t) => t.channel === "front");
      if (keep && hasFront) continue;
      const others = clip.tracks.filter((t) => t.channel !== "front");
      const keyed = draft({ ...clip, tracks: others }, dir === "accents");
      const summary = Object.entries(keyed)
        .map(
          ([arm, keys]) =>
            `${arm} ${keys.map((k) => `${k.t}:${k.v}`).join(" ")}`,
        )
        .join(" | ");
      if (summary || hasFront)
        console.log(`${name}: ${summary || "(behind throughout)"}`);
      if (!write || (!summary && !hasFront)) continue;
      const text = readFileSync(path, "utf8");
      const out = rewrite(text, keyed);
      const parsed = JSON.parse(out);
      const want = [
        ...others,
        ...Object.entries(keyed).map(([part, keys]) => ({
          part,
          channel: "front",
          keys,
        })),
      ];
      if (JSON.stringify(parsed.tracks) !== JSON.stringify(want))
        throw new Error(`${name}: rewrite changed other tracks`);
      if (out !== text) writeFileSync(path, out);
    }
  }
}
