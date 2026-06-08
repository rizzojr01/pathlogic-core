# AR Path Re-Anchoring (Option A)

Render the AR overlay from the **user's current pose** every frame
instead of from the session-start origin. Cumulative drift becomes
local-only drift.

---

## The change

`_handleArOverlay` in `ar_navigation_bloc.dart` previously built each
path vertex relative to a **static anchor** captured at navigation
start:

```text
floorplan_point (px, py)
        │
        ▼
delta from REFERENCE FP pose   (set once, at server localization)
        │ rotate by sumHeadingDeg
        ▼
delta from ORIGIN AR pose      (set once, at session start)
        │
        ▼
ARKit world-space (worldX, floorY, worldZ)
```

Now it anchors at the **live, snapped** user pose every frame:

```text
floorplan_point (px, py)
        │
        ▼
delta from CURRENT snapped FP pose   (updated every frame)
        │ rotate by sumHeadingDeg
        ▼
delta from CURRENT AR-world camera pos (updated every frame)
        │
        ▼
ARKit world-space (worldX, floorY, worldZ)
```

`sumHeadingDeg = reference.heading + origin.heading + arHeadingOffsetDeg`
is unchanged — it's the rotation between the floorplan and AR-world
frames, and rotation is a session-level constant. Only the anchor
moved.

---

## Why this fixes the wall-drift bug

Suppose the rotation is wrong by 5°.

**Before (static anchor):**

- Path origin frozen at session-start AR world position.
- After walking 12 m down a corridor, the next waypoint marker is
  `12 m × tan(5°) ≈ 1.05 m` to one side. Marker sits in the wall.

**After (re-anchor every frame):**

- Path origin = wherever the user is right now.
- Next waypoint is, say, 3 m ahead in floorplan.
- Marker offset: `3 m × tan(5°) ≈ 0.26 m`. Inside the corridor.
- As the user approaches the waypoint, the FP distance shrinks, so the
  AR offset shrinks too. The marker locks onto the right spot before
  the user reaches it.

The error doesn't disappear — but it can never accumulate beyond the
distance from the user to the next visible waypoint. For typical
corridor segments (3–8 m), the lateral error is sub-meter even with a
5° rotation bug.

---

## Why it doesn't make the path visibly slide

The floorplan pose is derived from the AR pose by
`ArPoseTransformer.transform(...)`. So when the user takes a step:

- AR world: `(x, z)` → `(x + Δx, z + Δz)`.
- Floorplan: `(px, py)` → `(px + Δpx, py + Δpy)` where the deltas are
  the exact same step expressed in the other coordinate frame.

Both anchors move by the same amount in lockstep, so any path vertex
that was at AR world `(wx, wy, wz)` last frame is still at
`(wx, wy, wz)` this frame. The path looks world-stable. Only when
`sumHeadingDeg` is *wrong* does the rendered position differ from the
real corridor — and that error now lives in the short delta from user
to waypoint, not in the long delta from origin to waypoint.

This relies on snap-to-route + the heading offset roughly tracking the
true session rotation. If both `sumHeadingDeg` AND the snap are wildly
wrong, the path will jitter. In practice neither is — snap is pinned
to the navmesh, and the offset slider (or auto-heading correction)
keeps `sumHeadingDeg` within a few degrees of truth.

---

## Tradeoffs

**Pros**

- Lateral drift is now bounded by the distance to the next waypoint
  (typically ≤ 5 m), not by total walk distance.
- No new state, no new toggle, no native code. Pure math swap inside
  one helper.
- Stacks cleanly with auto-heading correction and snap-to-route — they
  each attack a different layer of the problem.
- The path "follows" the user in a way that feels more responsive: the
  start of the line is always under the user's feet, not floating in
  space at the door they entered through.

**Cons**

- The far end of the path (distant waypoints, destination marker) can
  still be off by `total_path_length × tan(error)`. Re-anchoring helps
  the *near* part of the path, not the far end. Mitigation: pair with
  auto-heading or wall-driven correction to reduce the rotation error
  itself.
- If `currentArPose` is briefly stale (one frame where ARKit lost
  tracking and confidence dropped), the path will momentarily skip.
  This is the same risk that already affects the blue dot — accepting
  it here is consistent.
- The path's floor height now follows the camera height every frame.
  If the user tilts the phone toward the ceiling, the path follows.
  This is correct behaviour but a perceptible change from the
  session-start-anchored version.

---

## Files touched

| File                                                                    | Change                                                                                |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `lib/features/ar_navigation/presentation/bloc/ar_navigation_bloc.dart`  | `_handleArOverlay` now takes the current `ArPose`; anchor swapped from origin to live. |

That's the whole change. No service interfaces moved, no DI updates,
no UI work, no persistence keys.

---

## Testing checklist

1. **Drift-into-wall test (the actual symptom).** Localize, then walk a
   straight 15 m corridor. Watch the next waypoint marker. Before this
   change, marker drifts sideways; after, marker holds near the corridor
   centreline.
2. **Smoothness.** Stop and turn 360° in place. Path should rotate
   around the user without snapping, sliding, or duplicating.
3. **Floor height.** Hold the phone at waist height vs eye level. Path
   should sit at knee height in both — the constant `pathHeightOffsetM`
   is computed against the live camera height.
4. **Distant end.** Look at the destination marker from far away. It
   may still be slightly off — that's expected and is what
   auto-heading / wall-detection branches are for.
5. **Combined behaviour.** With auto-heading correction enabled,
   convergence should be visibly faster: as the slider self-corrects
   the rotation, the *near* part of the path snaps into correctness
   immediately (re-anchoring) and the *far* end converges over a few
   seconds of walking (auto-heading).
