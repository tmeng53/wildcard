// 排队入场, ported from the app (ios/Packages/Avatar, AvatarUI's `Lineup`): a squad along the edge of
// a screen. Up to five stand in one row, figure against figure, centered; more walk through in a
// queue that loops, coming in from the right and leaving on the left with a small hop. Lengths are
// at the design's figure height of 96 and scale with the strip's height; the caller passes the time.

export const ROW_LIMIT = 5;
const DESIGN_HEIGHT = 96;

/** The strip for `count` members, `width` wide and `height` tall (the figures' height). */
export function lineup(count, width, height) {
  const k = height / DESIGN_HEIGHT;
  // The design's strip (approved 2026-10-22): 72 × 96 figures, walkers 78 apart at 30 a second, hopping 5.
  const figureWidth = 72 * k;
  const gap = 78 * k;
  const pace = 30 * k;
  const hop = 5 * k;
  const walks = count > ROW_LIMIT;

  /** Each member's { left, lift } at `time` seconds, in the order given. */
  function spots(time) {
    if (!walks) {
      const middle = (count - 1) / 2;
      return Array.from({ length: count }, (_, i) => ({
        left: width / 2 - figureWidth / 2 + (i - middle) * figureWidth,
        lift: 0,
      }));
    }
    // At least a strip and a walker long, so a walker always comes back in past the right edge.
    const loop = Math.max(count * gap, width + gap);
    return Array.from({ length: count }, (_, i) => {
      const along = i * gap - time * pace;
      const wrapped = ((along % loop) + loop) % loop;
      // 2.4 hops a second, each member a little out of step with the one before.
      const lift = Math.abs(Math.sin((time + i * 0.37) * Math.PI * 2.4)) * hop;
      return { left: wrapped - gap, lift };
    });
  }

  /** Everyone standing still, for reduced motion: the row, or as many walkers as fit, centered. */
  function rest() {
    if (!walks) return spots(0);
    const fits = Math.max(1, Math.floor((width - figureWidth) / gap) + 1);
    const start = (width - ((fits - 1) * gap + figureWidth)) / 2;
    return Array.from({ length: count }, (_, i) => ({ left: start + i * gap, lift: 0 }));
  }

  return { figureWidth, walks, spots, rest };
}
