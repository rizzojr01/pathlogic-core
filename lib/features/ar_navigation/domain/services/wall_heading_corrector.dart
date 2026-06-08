import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Derives a new AR heading offset directly from the LiDAR-observed dominant
/// wall direction. Stronger signal than the walk-based corrector because it
/// does not require the user to walk: a single high-confidence wall
/// observation already pins the corridor orientation.
///
/// Math:
///   The bloc renders the AR path via `floorplanToArWorld` using
///   `sumHeadingDeg = reference.heading + captureHeading + offset`. A
///   floorplan direction `d_fp` maps to AR-world by CCW rotation through
///   `sumHeadingDeg`. Inverting:
///
///       d_fp = d_ar  −  sumHeadingDeg     (angles, mod 180 for walls)
///
///   We want the observed corridor direction in floorplan to equal the
///   nearest segment direction:
///
///       d_seg_fp ≡ d_corridor_ar − sumHeadingDeg
///   →   sumHeadingDeg ≡ d_corridor_ar − d_seg_fp
///   →   offset = (d_corridor_ar − d_seg_fp) − reference.heading − captureHeading
///
///   Walls give us `d_wall_ar` (mod 180); the corridor is perpendicular, so
///   `d_corridor_ar = d_wall_ar + 90°`. The 180° ambiguity is resolved by
///   picking the candidate closest to the current offset.
class WallHeadingCorrector {
  WallHeadingCorrector({
    this.minConfidence = 0.35,
    this.minSampleCount = 80,
    this.emaAlpha = 0.75,
    this.maxPerCallDeltaDeg = 0.8,
    this.maxCorrectionDeg = 12.0,
  });

  /// Reject low-confidence wall snapshots (corridor not well-defined).
  final double minConfidence;

  /// Reject very small mesh samples (still warming up).
  final int minSampleCount;

  /// EMA weight applied to the current offset. Larger = slower convergence
  /// but smoother. Walls update at ~2 Hz so we can be more aggressive than
  /// the walk-based corrector.
  final double emaAlpha;

  /// Cap on per-observation offset change. Prevents visible AR jitter.
  final double maxPerCallDeltaDeg;

  /// Refuse to apply if the implied correction exceeds this — likely a
  /// junction with multiple corridor directions or a flaky observation.
  final double maxCorrectionDeg;

  /// Returns the new proposed `arHeadingOffsetDeg`, or null if no safe
  /// update is available. All angles are degrees.
  double? observe({
    required double wallDominantYawDeg,
    required double wallConfidence,
    required int wallSampleCount,
    required Offset snappedFpPose,
    required List<(Offset, Offset)> segments,
    required double currentOffsetDeg,
    required double referenceHeadingDeg,
    required double captureHeadingDeg,
  }) {
    if (segments.isEmpty) return null;
    if (wallConfidence < minConfidence) return null;
    if (wallSampleCount < minSampleCount) return null;

    final segment = _nearestSegment(snappedFpPose, segments);
    if (segment == null) return null;

    // Segment direction in floorplan math plane (y-flip from image space).
    final segDx = segment.$2.dx - segment.$1.dx;
    final segDy = -(segment.$2.dy - segment.$1.dy);
    if ((segDx * segDx + segDy * segDy) <= 1e-6) return null;
    final segDirDeg = _atan2Deg(segDy, segDx);

    // Corridor direction in AR-world (perpendicular to dominant wall).
    final corridorYawArDeg = _normalizeDeg(wallDominantYawDeg + 90.0);

    // Target sumHeading is corridorYawAr − segDir (mod 180).
    final targetSumHeading = _normalizeDeg(corridorYawArDeg - segDirDeg);

    // Compute both candidate offsets (mod 180 ambiguity) and pick the one
    // closest to the current offset.
    final candidateA = _normalizeSignedDeg(
        targetSumHeading - referenceHeadingDeg - captureHeadingDeg);
    final candidateB = _normalizeSignedDeg(candidateA + 180.0);
    final deltaA = (candidateA - currentOffsetDeg).abs();
    final deltaB = (candidateB - currentOffsetDeg).abs();
    final target = deltaA <= deltaB ? candidateA : candidateB;

    final rawCorrection = _signedDeltaDeg(currentOffsetDeg, target);
    if (rawCorrection.abs() > maxCorrectionDeg) return null;

    final blendedDelta = (1.0 - emaAlpha) * rawCorrection;
    final clamped =
        blendedDelta.clamp(-maxPerCallDeltaDeg, maxPerCallDeltaDeg);
    if (clamped.abs() < 1e-3) return null;
    return currentOffsetDeg + clamped;
  }

  (Offset, Offset)? _nearestSegment(
    Offset point,
    List<(Offset, Offset)> segments,
  ) {
    double bestDistSq = double.infinity;
    (Offset, Offset)? best;
    for (final seg in segments) {
      final a = seg.$1;
      final b = seg.$2;
      final abDx = b.dx - a.dx;
      final abDy = b.dy - a.dy;
      final abLenSq = abDx * abDx + abDy * abDy;
      if (abLenSq <= 1e-6) continue;
      final apDx = point.dx - a.dx;
      final apDy = point.dy - a.dy;
      final t = ((apDx * abDx) + (apDy * abDy)) / abLenSq;
      final clampedT = t.clamp(0.0, 1.0);
      final projDx = a.dx + abDx * clampedT;
      final projDy = a.dy + abDy * clampedT;
      final dx = point.dx - projDx;
      final dy = point.dy - projDy;
      final dSq = dx * dx + dy * dy;
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        best = seg;
      }
    }
    return best;
  }

  static double _atan2Deg(double y, double x) =>
      _normalizeDeg(math.atan2(y, x) * 180.0 / math.pi);

  static double _normalizeDeg(double v) {
    var n = v % 360.0;
    if (n < 0) n += 360.0;
    return n;
  }

  static double _normalizeSignedDeg(double v) {
    var n = v % 360.0;
    if (n > 180.0) n -= 360.0;
    if (n < -180.0) n += 360.0;
    return n;
  }

  static double _signedDeltaDeg(double from, double to) {
    var d = (to - from + 540.0) % 360.0 - 180.0;
    if (d < -180.0) d += 360.0;
    return d;
  }
}
