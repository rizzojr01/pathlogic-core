import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Produces a single, stable device heading by fusing the gyroscope with the
/// magnetometer-based compass.
///
/// Why: indoors the raw magnetometer is unreliable — rebar, wiring, elevators
/// and metal shelving bend magnetic north, so `FlutterCompass` reports a
/// *different* heading for the *same* physical direction depending on where you
/// walked. That is what made the map's rotation "sometimes wrong" after moving
/// around and returning to the same spot.
///
/// The gyroscope, by contrast, measures rotation directly and is immune to
/// magnetic fields. It drifts slowly over minutes, but is rock-solid over the
/// seconds/minutes of a navigation session.
///
/// Complementary filter (runs on every gyro sample):
/// ```
///   fused += gyroYawDelta                       // fast, spike-free prediction
///   fused += gain * shortestArc(compass - fused)// slow absolute correction
/// ```
/// The gyro drives short-term motion (so turning the phone updates the map
/// instantly and magnetic spikes are ignored); the compass only nudges the
/// fused value slowly toward absolute north, cancelling long-term gyro drift.
///
/// Output is a broadcast [Stream] of headings in degrees, `[0, 360)`.
class HeadingFusionService {
  HeadingFusionService();

  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  /// Fused heading in degrees `[0, 360)`. Emits on every gyroscope sample once
  /// an initial magnetic fix has seeded it (falls back to raw compass if the
  /// gyroscope is unavailable).
  Stream<double> get headingStream => _controller.stream;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<CompassEvent>? _compassSub;

  // Fused heading in degrees [0,360). null until the first compass fix seeds it.
  double? _fused;

  // Latest tilt-compensated magnetic heading + its reported accuracy (degrees).
  double? _magHeading;
  double? _magAccuracy;

  // Low-passed accelerometer = gravity/up direction in the device frame. Used
  // to project the gyro angular-velocity vector onto the world-vertical axis so
  // yaw is extracted correctly regardless of how the phone is tilted.
  double _ax = 0, _ay = 0, _az = 9.81;
  bool _gravityInit = false;

  // True once at least one gyroscope sample has arrived. Until then the raw
  // compass is forwarded directly so heading still works on gyro-less devices.
  bool _hasGyro = false;

  final Stopwatch _stopwatch = Stopwatch();

  // ── Tuning ────────────────────────────────────────────────────────────────
  static const double _gravityLpf = 0.9; // heavier = steadier up-vector estimate
  static const double _magGain = 0.03; // absolute-correction speed (per sample)
  static const double _spikeRejectDeg = 25.0; // ignore compass jumps larger than this
  // Sign of the yaw integration. Reasoned for the standard Android/iOS sensor
  // frame; flip to -1.0 if on-device the map rotates the wrong way when turning.
  static const double _yawSign = 1.0;

  bool get isRunning => _gyroSub != null || _compassSub != null;

  void start() {
    if (isRunning) return;
    _stopwatch
      ..reset()
      ..start();

    _compassSub = FlutterCompass.events?.listen((e) {
      final h = e.heading;
      if (h == null || h.isNaN || h.isInfinite || h < 0) return;
      _magHeading = _norm360(h);
      _magAccuracy = e.accuracy;
      // Seed the fused heading from the first valid magnetic fix.
      _fused ??= _magHeading;
      // Gyro-less fallback: keep emitting the raw compass so heading still works.
      if (!_hasGyro && _fused != null && !_controller.isClosed) {
        _controller.add(_fused!);
      }
    });

    _accelSub = accelerometerEventStream().listen(
      (e) {
        if (!_gravityInit) {
          _ax = e.x;
          _ay = e.y;
          _az = e.z;
          _gravityInit = true;
        } else {
          _ax = _gravityLpf * _ax + (1 - _gravityLpf) * e.x;
          _ay = _gravityLpf * _ay + (1 - _gravityLpf) * e.y;
          _az = _gravityLpf * _az + (1 - _gravityLpf) * e.z;
        }
      },
      onError: (_) {},
    );

    _gyroSub = gyroscopeEventStream().listen(
      (e) {
        final dt = _stopwatch.elapsedMicroseconds / 1e6;
        _stopwatch.reset();
        _hasGyro = true;

        // Skip the first sample and any stalled gap (app backgrounded, etc.).
        if (dt <= 0 || dt > 0.5) return;
        // Wait for the first compass fix to anchor absolute north.
        if (_fused == null) return;

        // Unit up-vector (accelerometer points opposite gravity ⇒ toward sky).
        final norm = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
        if (norm < 1e-3) return;
        final ux = _ax / norm, uy = _ay / norm, uz = _az / norm;

        // Angular velocity about the world-vertical axis (rad/s).
        final yawRate = e.x * ux + e.y * uy + e.z * uz;

        // A right-hand-positive rotation about the up-vector is counter-clockwise
        // seen from above ⇒ compass heading DECREASES, hence the leading minus.
        final dHeadingDeg = -_yawSign * yawRate * dt * 180.0 / math.pi;

        var fused = _fused! + dHeadingDeg;

        // Slow absolute correction toward the compass, with spike rejection so a
        // sudden magnetic distortion can't yank the heading.
        final mag = _magHeading;
        if (mag != null) {
          final err = _shortestArc(mag - fused);
          final acc = _magAccuracy;
          final trustworthy = acc == null || (acc >= 0 && acc <= 20);
          if (err.abs() <= _spikeRejectDeg && trustworthy) {
            fused += _magGain * err;
          }
        }

        _fused = _norm360(fused);
        if (!_controller.isClosed) _controller.add(_fused!);
      },
      onError: (_) {},
    );
  }

  void stop() {
    _gyroSub?.cancel();
    _gyroSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _stopwatch.stop();
    _hasGyro = false;
    _gravityInit = false;
    _fused = null;
    _magHeading = null;
    _magAccuracy = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  static double _shortestArc(double d) {
    d %= 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  static double _norm360(double d) {
    d %= 360;
    if (d < 0) d += 360;
    return d;
  }
}
