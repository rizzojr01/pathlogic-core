# Snap-to-Route Feature — Implementation Guide

End-to-end spec for porting the snap-to-route feature to another codebase.
Covers: problem, algorithm, data contract, code-by-code reference, and a
language-agnostic port checklist.

---

## 1. Problem

Indoor localization (server VPS + on-device ARKit) returns a pose `(x, y)` in
floorplan pixel coordinates. Two failure modes hurt UX:

1. **Server pose noise** — VPS-localized pose can land a few pixels *off* a
   corridor (in a wall, in a room, between corridors). The blue dot looks
   broken even when localization is fundamentally correct.
2. **ARKit drift** — between VPS fixes, the continuous ARKit pose drifts off
   the route slowly. The blue dot wanders away from the corridor.

**Snap-to-route fix:** project the raw pose onto the nearest navigable route
edge before displaying or path-tracking. The blue dot always sits on a real
walkable line.

Tradeoff: snap hides real off-route errors (user is genuinely off route but
display shows them on it). For that reason it's user-toggleable.

---

## 2. The geometric core: point-to-segment projection

This is the only math in the feature. Given:

- a point `P = (px, py)` (user's pose)
- a list of segments `[(A_i, B_i)]` where each `A_i, B_i` is `(x, y)`

For each segment `(A, B)`:

1. `AB = B - A`
2. `|AB|^2 = AB.x*AB.x + AB.y*AB.y`
3. If `|AB|^2 < epsilon` → degenerate segment, skip
4. `AP = P - A`
5. `t = (AP · AB) / |AB|^2`  (scalar projection parameter, dimensionless)
6. `t_clamped = clamp(t, 0.0, 1.0)`  (keeps projection ON the segment, not on
   its infinite extension)
7. `projection = A + AB * t_clamped`
8. `dist^2 = (P.x - projection.x)^2 + (P.y - projection.y)^2`

Track the projection with the smallest `dist^2` across all segments. That is
the snapped point.

**Optional threshold:** if `dist^2 > threshold^2`, return the original `P`
instead. Use this when you don't want a far-away pose to be yanked onto a
distant route line.

### Reference impl (Dart) — `lib/core/utils/route_snap.dart`

```dart
import 'dart:ui';

Offset snapToRouteNetwork(
  Offset point,
  List<(Offset, Offset)> segments, {
  double? thresholdPx,
}) {
  if (segments.isEmpty) return point;

  double bestDistSq = double.infinity;
  Offset best = point;

  for (final (a, b) in segments) {
    final ab = b - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLenSq <= 1e-6) continue;

    final ap = point - a;
    final t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / abLenSq;
    final proj = a + ab * t.clamp(0.0, 1.0);

    final dx = point.dx - proj.dx;
    final dy = point.dy - proj.dy;
    final dSq = dx * dx + dy * dy;

    if (dSq < bestDistSq) {
      bestDistSq = dSq;
      best = proj;
    }
  }

  if (thresholdPx != null && bestDistSq > thresholdPx * thresholdPx) {
    return point;
  }
  return best;
}
```

Port to any language: identical math, replace `Offset` with whatever 2-D
point type exists in your codebase.

---

## 3. Data contract — what backend must return

### 3.1 Ideal (full route graph, used in this repo)

Backend returns in `unav_navigation` response:

```json
"route_segments": [
  { "from": [x1, y1], "to": [x2, y2] },
  { "from": [x2, y2], "to": [x3, y3] },
  ...
]
```

- Pixel coordinates in the current floorplan image
- Every navigable corridor edge on the current floor (full graph)
- Allows snap to *any* corridor — robust when user wanders off chosen route

### 3.2 Minimum viable (chosen-path only, what your other backend gives)

`navigation_steps` already has the geometry:

```json
"navigation_steps": [
  {
    "from": { "x": 1739.80, "y": 1146.18 },
    "to":   { "x": 1970.83, "y": 1156.25 },
    "distance_meters": 5.10,
    "compass_direction": "Front",
    ...
  },
  ...
]
```

- Same pixel coordinates
- Only the chosen path, not the full graph
- Snap works while user is near the chosen route. If user strays, snap pulls
  them back onto the chosen route (no nearby alt corridor to fall on)

Extract just `from` + `to` per step → feed to algorithm.

### 3.3 Other data you need from the response

These are NOT part of snap itself but are required to render the blue dot +
route lines at all:

| Need | Why | Typical field |
|---|---|---|
| User pose `(x, y)` | the point you snap | `floorplan_pose.x`, `.y` |
| User heading (deg) | to draw arrow / decide off-route side | `floorplan_pose.ang` |
| Floor identifier | choose which floorplan to render on | `best_map_key` |
| Floorplan image | canvas to draw on | URL or asset path |
| Chosen path coords | the yellow/lime route line | `path_coords` |
| Meters-per-pixel (optional) | converts pixel thresholds → meter thresholds | derived from map |

---

## 4. Where snap is applied (two call sites)

Snap must be applied at every place the pose enters the display/tracking
pipeline. In this repo there are exactly two:

### 4.1 On the initial VPS-localized pose

When a new `unav_navigation` response arrives, the server-localized pose is
parsed and immediately snapped before it becomes the session anchor.

**File:** `lib/features/navigation/domain/services/navigation_result_parser.dart`

```dart
var pose = parseFloorplanPose(result, mapKey);
if (snapToRoute && pose != null && routeNet.isNotEmpty) {
  final snapped = snapToRouteNetwork(Offset(pose.x, pose.y), routeNet);
  pose = LocalizedPose(
    floorKey: pose.floorKey,
    x: snapped.dx,
    y: snapped.dy,
    heading: pose.heading,         // heading unchanged
    confidence: pose.confidence,
    timestamp: pose.timestamp,
  );
}
```

Heading, confidence, timestamp are NOT changed — only `x`, `y`.

### 4.2 On every ARKit frame

Between server fixes, native ARKit emits pose updates 30–60 times per second.
Each must be snapped before being used for off-route detection and rendering.

**File:** `lib/features/navigation/domain/services/path_tracking_service.dart`

```dart
final rawPoint = Offset(pose.x, pose.y);
final routeNet = route.routeNetworkSegments;
final currentPoint = snapToRoute && routeNet.isNotEmpty
    ? snapToRouteNetwork(rawPoint, routeNet)
    : rawPoint;
// ... use currentPoint for all downstream projection/distance math
```

Cost: O(N) per frame where N = segments on floor. For typical buildings
(~hundreds of edges) this is negligible. No spatial index needed unless N
explodes to thousands.

---

## 5. Drawing the route network (the faint blue lines)

The full graph is drawn underneath the chosen path as a visual hint so the
user can see all corridors.

**File:** `lib/widgets/floorplan_path_painter.dart`

```dart
if (routeNetworkSegments.isNotEmpty) {
  final routePaint = Paint()
    ..color = Colors.lightBlue.withValues(alpha: 0.35)  // faint
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  for (final (a, b) in routeNetworkSegments) {
    canvas.drawLine(
      Offset(a.dx * scale + offset.dx, a.dy * scale + offset.dy),
      Offset(b.dx * scale + offset.dx, b.dy * scale + offset.dy),
      routePaint,
    );
  }
}
```

Two render modes — overview and first-person — both draw the network. In
overview mode segments are transformed by `(coord * scale + offset)`. In
first-person mode the canvas itself is translated/rotated/scaled around the
user, so segments are drawn in raw floorplan coords with no per-point
transform.

Important draw-order: floorplan image → route network (faint) → chosen path
(bright) → endpoints → heading arrow. Network must be UNDER the chosen path
so the chosen route stays visually dominant.

---

## 6. User toggle (the "Snap" pill button)

The user can disable snap at runtime (when debugging localization, the user
wants to see the raw pose).

### Wiring (top-down)

1. **UI flag in screen state** (`lib/screens/navigation_screen.dart`):
   ```dart
   bool _snapToRoute = true;
   ```

2. **Pill toggle button** (around `navigation_screen.dart:1344`):
   ```dart
   GestureDetector(
     onTap: () {
       setState(() {
         _snapToRoute = !_snapToRoute;
         _navigationController.snapToRoute = _snapToRoute;
       });
     },
     child: AnimatedContainer(
       /* lime when on, black54 when off */
       child: Row(children: [Icon(Icons.route, size: 14), Text('Snap')]),
     ),
   ),
   ```

3. **Controller exposes mutable flag** (`navigation_controller.dart:57`):
   ```dart
   bool snapToRoute = true;
   ```

4. **Threaded into parser + tracker on every update** (each `update` /
   `parse` call passes `snapToRoute: this.snapToRoute`).

The flag is read fresh on every call so toggling takes effect on the next
frame — no rebuild of services needed.

---

## 7. End-to-end data flow

```
                ┌────────────────────────────────┐
                │ Backend `unav_navigation` resp │
                │   - floorplan_pose (x,y,ang)   │
                │   - path_coords (chosen route) │
                │   - route_segments (graph)     │  ← or navigation_steps
                └─────────────┬──────────────────┘
                              │
                  NavigationResultParser.parse(snapToRoute)
                              │
                  ┌───────────┴──────────────┐
                  ▼                          ▼
         routeNetworkSegments        LocalizedPose (snapped if flag on)
                  │                          │
                  │              session.localizedAnchorPose
                  │                          │
                  │              ARKit pose stream ───────┐
                  │                          │             │
                  │                          ▼             │
                  │             PathTrackingService.update(snapToRoute)
                  │                          │
                  │                  rawPoint = (pose.x, pose.y)
                  │                  currentPoint = snapToRouteNetwork(raw, routeNet)
                  │                          │
                  │                  off-route detection, waypoint advance,
                  │                  distance remaining, guidance events
                  │                          │
                  └──────────┐               │
                             ▼               ▼
                     FloorplanPathPainter.paint()
                       - draws routeNetworkSegments (faint blue)
                       - draws chosen path (lime/yellow)
                       - draws blue dot at currentPoint
                       - draws heading arrow
```

---

## 8. Port checklist (language-agnostic)

Step-by-step, in order, for porting to another codebase:

- [ ] **Parse network segments.** From response, build a list of
      `(from_xy, to_xy)` tuples. Handle both object form `{x,y}` and array
      form `[x,y]`. Skip malformed entries silently.
- [ ] **Implement `snapToRouteNetwork(point, segments, thresholdPx?)`.**
      Copy algorithm in §2 verbatim. Unit-test with known geometry.
- [ ] **Wire into pose parsing.** Wherever the VPS-localized pose is
      extracted from the response, snap it before storing. Only mutate
      `x, y` — leave heading, confidence, timestamp alone.
- [ ] **Wire into ARKit/SLAM frame handler.** On every pose update, snap
      `raw → current` before any downstream math (off-route distance,
      waypoint advance, painter).
- [ ] **Draw network as faint background layer.** Underneath the chosen
      path, above the floorplan image. ~35% alpha light-blue, ~2.5 px width.
- [ ] **Add toggle.** A boolean flag, mutable, threaded into both call
      sites. UI is a small pill/checkbox/switch.
- [ ] **Handle empty segments.** If `route_segments` is empty/missing, snap
      is a no-op. Never crash, never block other functionality.
- [ ] **Backend mismatch fallback.** If your backend only gives
      `navigation_steps`, extract `from`/`to` from each step (object form).
      Document the limitation: snap only to chosen path.

---

## 9. Pitfalls observed

| Pitfall | Cause | Fix |
|---|---|---|
| Blue dot teleports far away on first frame | Threshold not set, far stray pose snapped onto distant edge | Pass `thresholdPx` (e.g. 100 px); fall back to raw point if exceeded |
| Off-route detection stops triggering | Snap hides the off-route distance from `_projectToPath` | Compute off-route distance from RAW pose, snap only for display. (Current repo intentionally uses snapped point — accept the tradeoff or split.) |
| Snap drags pose onto wrong floor's segments | Segments list mixes floors | Always filter `routeNetworkSegments` to current floor before passing in |
| Degenerate zero-length segment crashes / NaN | `|AB|^2 = 0` division | `if (abLenSq <= 1e-6) continue;` — already handled |
| Pill toggle has no effect | Flag captured by closure at service construction time | Read flag fresh on every call, don't store it in the service |

---

## 10. File index (this repo)

| File | Role |
|---|---|
| `lib/core/utils/route_snap.dart` | Pure geometric snap function |
| `lib/core/models/navigation_route.dart` | `routeNetworkSegments` field on route model |
| `lib/features/navigation/domain/services/navigation_result_parser.dart` | Parses `route_segments`; snaps server pose |
| `lib/features/navigation/domain/services/path_tracking_service.dart` | Snaps ARKit pose each frame |
| `lib/features/navigation/application/navigation_controller.dart` | Owns mutable `snapToRoute` flag; threads it through |
| `lib/widgets/floorplan_path_painter.dart` | Draws network layer + chosen path + blue dot |
| `lib/screens/navigation_screen.dart` | UI pill button toggling the flag |

---

## 11. Commits that introduced it (this repo)

- `f4f73e1` — `nav: snap-to-route-network on floorplan display and ARKit tracking`
  - Adds `route_snap.dart`, `routeNetworkSegments`, snapping in parser +
    tracker, faint layer in painter.
- `2ae0d8a` — `feat(nav): add snap-to-route toggle button on navigation screen`
  - Adds the runtime toggle and threads `snapToRoute` flag through the
    pipeline.

Read these two diffs in order — they are the complete minimal patch set.
