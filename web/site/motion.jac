"""Scroll-scrubbing math.

The transformation section is driven by a single scalar — how far the reader has
scrolled through the section, 0 to 1. Every moving part is a pure function of
that scalar, which is what makes the sequence replayable: scrolling back up runs
it backwards with no state to unwind.

`cl` markers are load-bearing — this module has no JSX and no npm import, so
inference would otherwise place it server-side.
"""

cl def:pub clamp01(x: float) -> float {
    if x < 0.0 { return 0.0; }
    if x > 1.0 { return 1.0; }
    return x;
}

"""Local 0..1 progress for a stage occupying [a, b] of the global scroll."""
cl def:pub ramp(p: float, a: float, b: float) -> float {
    if b <= a { return 0.0; }
    return clamp01((p - a) / (b - a));
}

"""easeOutCubic — fast arrival, soft landing. Reads as weight."""
cl def:pub ease_out(t: float) -> float {
    u: float = 1.0 - t;
    return 1.0 - u * u * u;
}

"""easeInCubic — the mirror, for things leaving."""
cl def:pub ease_in(t: float) -> float {
    return t * t * t;
}

"""Round to `steps` buckets.

Used on values handed to `react-force-graph-2d`: the scroll handler fires ~60
times a second, and re-rendering the canvas component that often to nudge an
alpha by 0.004 is wasted work. Quantising means the graph re-renders a couple of
dozen times across the whole scroll instead of thousands, and at these ramp
lengths the stepping is invisible.
"""
cl def:pub quantize(x: float, steps: int) -> float {
    return (round(x * (steps as float)) as float) / (steps as float);
}
