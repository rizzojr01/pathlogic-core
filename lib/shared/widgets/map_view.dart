import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:fuzzy/fuzzy.dart';

import '../../features/destination/domain/entities/destination_entity.dart';
import '../../features/locate_me/domain/entities/user_position_entity.dart';
import '../../features/navigation/domain/entities/location_entity.dart';
import '../../features/navigation/domain/entities/route_entity.dart';
import 'map_controls_widget.dart';
import 'map_markers.dart';
import '../../injection.dart';
import '../services/map_download_service.dart';
import 'map_search_overlay.dart';
import '../services/location_config_service.dart';

class MapView extends StatefulWidget {
  final dynamic userLocation;
  final RouteEntity? route;
  final String floorPlanBase64;
  final Function(DestinationEntity)? onDestinationTap;
  final List<DestinationEntity> destinations;
  final VoidCallback? onRetry;
  final VoidCallback? onRelocalize;
  final bool autoCenterOnUser;
  final String? currentFloor;
  final bool isCheckpoint;
  final double mapControlsRightOffset;
  final double? headingAtStart;
  final double? capturedReferenceHeading;
  final bool showControls;
  final TransformationController? externalTransformController;

  const MapView({
    super.key,
    required this.userLocation,
    this.route,
    required this.floorPlanBase64,
    this.onDestinationTap,
    this.destinations = const [],
    this.onRetry,
    this.onRelocalize,
    this.autoCenterOnUser = true,
    this.currentFloor,
    this.isCheckpoint = false,
    this.headingAtStart,
    this.capturedReferenceHeading,
    this.mapControlsRightOffset = 0,
    this.showControls = true,
    this.externalTransformController,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  late AnimationController _routeAnimationController;
  // Uses external controller if provided (caller owns it); otherwise creates its own.
  late TransformationController _transformationController;
  bool _ownsTransformController = false;

  late AnimationController _snapRotationController;
  Animation<double>? _snapRotationAnimation;
  double _manualRotation = 0.0; // radians, current map rotation
  double _initialRouteRotation = 0.0; // radians, set from first route segment
  Matrix4? _initialMatrix; // transformation at initial view
  // Two-pointer rotation tracking
  final Map<int, Offset> _activePointers = {};
  double _lastPointerAngle = 0.0;
  double _gestureStartAngle = 0.0; // angle when second finger touched down
  bool _isTrackingRotation = false;
  bool _rotationThresholdMet = false; // only rotate after intentional twist
  static const double _rotationThreshold = 0.12; // ~7 degrees dead zone
  bool _showLegend = false;
  DestinationEntity? _selectedDestination;
  Uint8List? _floorPlanBytes;
  Size? _imageSize;
  bool _hasImageError = false;
  bool _isSearching = false;
  bool _hasInitializedView = false;
  bool _hasRecenteredOnUser = false;
  bool _hasSetInitialRotation = false;

  // Compass tracking and smooth interpolation
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _initialCompassHeading; // heading (degrees) when tracking started
  double _smoothedHeading = 0.0; // EMA-filtered heading, avoids noise spikes
  double _targetRotation = 0.0; // The rotation we want to reach (radians)
  late Ticker _rotationTicker;
  bool _headingInitialized = false;
  bool _compassActive = false; // true once tracking starts
  Timer? _compassStartTimer;

  // Configuration for rotation stability
  static const double _baseCompassAlpha = 0.20; // Smoothing factor for sensor
  static const double _tickerLerpFactor =
      0.35; // Speed of inter-frame smoothing

  final TextEditingController _searchController = TextEditingController();
  List<DestinationEntity> _filteredDestinations = [];

  @override
  void initState() {
    super.initState();
    if (widget.externalTransformController != null) {
      _transformationController = widget.externalTransformController!;
    } else {
      _transformationController = TransformationController();
      _ownsTransformController = true;
    }

    _routeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _snapRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _decodeFloorPlan();
    _filteredDestinations = widget.destinations;
    _searchController.addListener(_onSearchChanged);

    _rotationTicker = createTicker((_) {
      if (_manualRotation == _targetRotation) return;

      // Smoothly interpolate rotation using shortest arc in radians
      double diff = _targetRotation - _manualRotation;
      while (diff < -math.pi) diff += 2 * math.pi;
      while (diff > math.pi) diff -= 2 * math.pi;

      if (diff.abs() < 0.001) {
        _applyManualRotation(_targetRotation);
      } else {
        _applyManualRotation(_manualRotation + diff * _tickerLerpFactor);
      }
    })..start();
  }

  /// Updates [_manualRotation] and modifies the [TransformationController] to
  /// keep the user marker at its current screen position during the change.
  void _applyManualRotation(double newRotation) {
    if (_imageSize == null) {
      setState(() => _manualRotation = newRotation);
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      setState(() => _manualRotation = newRotation);
      return;
    }

    final cSize = box.size;
    final iAR = _imageSize!.width / _imageSize!.height;
    final cAR = cSize.width / cSize.height;
    double dispW, dispH;
    if (iAR > cAR) {
      dispW = cSize.width;
      dispH = cSize.width / iAR;
    } else {
      dispH = cSize.height;
      dispW = cSize.height * iAR;
    }
    final sX = dispW / _imageSize!.width;
    final sY = dispH / _imageSize!.height;
    final offX = (cSize.width - dispW) / 2;
    final offY = (cSize.height - dispH) / 2;
    final userPos = _getUserCoords();

    final userCX = userPos.dx * sX + offX;
    final userCY = userPos.dy * sY + offY;
    final cx = cSize.width / 2;
    final cy = cSize.height / 2;
    final dxU = userCX - cx;
    final dyU = userCY - cy;

    final cosOld = math.cos(_manualRotation);
    final sinOld = math.sin(_manualRotation);
    final oldX = cx + dxU * cosOld - dyU * sinOld;
    final oldY = cy + dxU * sinOld + dyU * cosOld;

    final cosNew = math.cos(newRotation);
    final sinNew = math.sin(newRotation);
    final newX = cx + dxU * cosNew - dyU * sinNew;
    final newY = cy + dxU * sinNew + dyU * cosNew;

    final shiftX = oldX - newX;
    final shiftY = oldY - newY;

    final newMatrix = _transformationController.value.clone()
      ..translate(shiftX, shiftY);

    setState(() {
      _manualRotation = newRotation;
      _transformationController.value = newMatrix;
    });
  }

  // ── compass ────────────────────────────────────────────────────────────────

  /// Starts compass tracking after [delay].
  /// Saves the heading at the moment tracking begins as the baseline,
  /// then applies: mapRotation = initialRouteRotation − deltaHeading.
  void _startCompassTracking({
    Duration delay = Duration.zero,
    double? seedHeading,
  }) {
    _compassStartTimer?.cancel();
    _compassStartTimer = Timer(delay, () {
      if (!mounted) return;
      _compassSubscription?.cancel();
      // Pre-seed the compass baseline:
      // • If seedHeading is provided (capture-time heading), use it directly.
      //   This anchors the delta calculation to the exact moment the photo was
      //   taken, so any phone movement DURING map loading is compensated for.
      // • Otherwise fall back to null, which means the first compass event
      //   will become the baseline (legacy behaviour).
      _initialCompassHeading = seedHeading;
      _compassSubscription = FlutterCompass.events?.listen((event) {
        final heading = event.heading;
        if (heading == null || !mounted) return;

        if (heading.isNaN || heading.isInfinite) return;

        // ── Exponential moving average (low-pass) filter ────────────────────
        // Raw magnetometer is very noisy indoors. EMA keeps the value stable
        // when stationary while still tracking real rotation smoothly.
        if (!_headingInitialized) {
          _smoothedHeading = heading;
          _headingInitialized = true;
        } else {
          // ── Adaptive Alpha ─────────────────────────────────────────────────
          // Smaller movements are filtered more aggressively for stability.
          // Larger, faster movements use a higher alpha for responsiveness.
          final rawArc = _shortestArc(heading - _smoothedHeading).abs();
          double alpha = _baseCompassAlpha;
          if (rawArc < 3) {
            alpha =
                _baseCompassAlpha *
                0.3; // Very slow changes = maximum stability
          } else if (rawArc > 10) {
            alpha =
                _baseCompassAlpha *
                2.5; // Intentional turns = high responsiveness
          }

          // If accuracy is poor, aggressively dampen the signal
          final accuracy = event.accuracy;
          if (accuracy != null && (accuracy > 15 || accuracy < 0)) {
            alpha *= 0.4;
          }

          // Interpolate using shortest arc to handle the 0↔360° wrap correctly
          final arc = _shortestArc(heading - _smoothedHeading);

          // ── Dead Zone ──────────────────────────────────────────────────────
          // If the movement is extremely small (noise), ignore it to prevent
          // the "jittering" effect when the phone is stationary.
          if (arc.abs() < 0.8) return; // Ignore movements < 0.8 degrees

          _smoothedHeading += alpha * arc;
          _smoothedHeading = _smoothedHeading % 360;
          if (_smoothedHeading < 0) _smoothedHeading += 360;
        }

        // Capture the baseline heading on the very first event
        _initialCompassHeading ??= _smoothedHeading;
        if (_initialCompassHeading!.isNaN) {
          _initialCompassHeading = _smoothedHeading;
        }

        // How many degrees has the user physically rotated since tracking began?
        final delta = _shortestArc(_smoothedHeading - _initialCompassHeading!);

        // Update the target rotation. The Ticker will smoothly interpolate
        // _manualRotation to reach this value.
        _targetRotation = _initialRouteRotation - delta * math.pi / 180.0;

        if (mounted) setState(() => _compassActive = true);
      });
    });
  }

  /// Returns the shortest signed arc (−180..+180) between two headings.
  double _shortestArc(double delta) {
    delta = delta % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }

  void _decodeFloorPlan() {
    try {
      if (widget.floorPlanBase64.isNotEmpty) {
        _floorPlanBytes = base64Decode(widget.floorPlanBase64);
        _loadImageSize();
      } else {
        _hasImageError = true;
      }
    } catch (e) {
      _hasImageError = true;
    }
  }

  void _loadImageSize() {
    if (_floorPlanBytes == null) return;
    final image = MemoryImage(_floorPlanBytes!);
    image
        .resolve(const ImageConfiguration())
        .addListener(
          ImageStreamListener((info, _) {
            if (mounted) {
              setState(() {
                _imageSize = Size(
                  info.image.width.toDouble(),
                  info.image.height.toDouble(),
                );
                if (widget.autoCenterOnUser) _setInitialRouteRotation();
              });
            }
          }),
        );
  }

  /// Rotates the map so the user's current facing direction points upward on screen.
  void _setInitialRouteRotation() {
    if (_hasSetInitialRotation) return;
    final route = widget.route;
    if (route == null || route.steps.isEmpty) return;
    _hasSetInitialRotation = true;

    final userAngleDeg = route.steps.first.from.ang ?? 0.0;

    // --- Synchronize initial rotation using headings from NavigationBloc ---
    // This ensures that even before the first compass event fires, the map
    // is oriented correctly relative to the user's physical movement between
    // shutter-press and map-load.
    double initialDelta = 0.0;
    if (widget.headingAtStart != null &&
        widget.capturedReferenceHeading != null) {
      initialDelta = _shortestArc(
        widget.headingAtStart! - widget.capturedReferenceHeading!,
      );
    }

    _manualRotation =
        -((userAngleDeg + initialDelta) * (math.pi / 180.0) + (math.pi / 2));
    _initialRouteRotation = -(userAngleDeg * (math.pi / 180.0) + (math.pi / 2));
    _targetRotation = _manualRotation;

    if (widget.route != null) {
      _startCompassTracking(seedHeading: widget.capturedReferenceHeading);
    }
  }

  /// Smoothly animates rotation AND position back to the initial view.
  void _snapToInitialRotation() {
    _snapRotationController.stop();

    final fromRotation = _manualRotation;
    final toRotation = _initialRouteRotation;
    final fromMatrix = _transformationController.value.clone();
    final toMatrix = _initialMatrix ?? _transformationController.value.clone();

    _snapRotationAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _snapRotationController,
            curve: Curves.easeInOutCubic,
          ),
        )..addListener(() {
          final t = _snapRotationAnimation!.value;
          // Interpolate rotation
          final newRotation = fromRotation + (toRotation - fromRotation) * t;
          // Interpolate each matrix entry
          final fromStorage = fromMatrix.storage;
          final toStorage = toMatrix.storage;
          final interpolated = Matrix4.fromList(
            List.generate(
              16,
              (i) => fromStorage[i] + (toStorage[i] - fromStorage[i]) * t,
            ),
          );
          setState(() => _manualRotation = newRotation);
          _transformationController.value = interpolated;
        });
    _snapRotationController.forward(from: 0);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredDestinations = widget.destinations;
      } else {
        final fuse = Fuzzy<DestinationEntity>(
          widget.destinations,
          options: FuzzyOptions(
            findAllMatches: true,
            tokenize: true,
            threshold: 0.4,
            keys: [
              WeightedKey(
                name: 'name',
                getter: (dest) => dest.name,
                weight: 0.6,
              ),
              WeightedKey(
                name: 'floor',
                getter: (dest) => dest.floor ?? '',
                weight: 0.4,
              ),
            ],
          ),
        );
        final results = fuse.search(query);
        _filteredDestinations = results.map((r) => r.item).toList();
      }
    });
  }

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floorPlanBase64 != widget.floorPlanBase64) {
      // Floor switched: reset ALL view/rotation state so the new floor is
      // oriented and centered using its own route data.
      //
      // _hasSetInitialRotation and _hasInitializedView MUST be reset here.
      // If they stay true, _setInitialRouteRotation() exits immediately on
      // the guard check, leaving the first floor's stale rotation applied to
      // the second floor's coordinate space — which is what put the checkpoint
      // marker off-map.
      setState(() {
        _imageSize = null;
        _hasRecenteredOnUser = false;
        _initialMatrix = null;
        _hasInitializedView = false;
        _hasSetInitialRotation = false;
        _selectedDestination = null;
      });
      _decodeFloorPlan();
    }
    if (oldWidget.destinations != widget.destinations) {
      _filteredDestinations = widget.destinations;
    }
    // If route arrives for the first time or identity changes, set initial rotation/view.
    // We compare entityId to avoid recentering when only debug offsets are updated.
    final bool headingChanged =
        oldWidget.capturedReferenceHeading != widget.capturedReferenceHeading ||
        oldWidget.headingAtStart != widget.headingAtStart;
    final bool routeStateChanged =
        oldWidget.route == null && widget.route != null;
    final bool routeIdentityChanged =
        oldWidget.route != null &&
        widget.route != null &&
        oldWidget.route!.entityId != widget.route!.entityId;

    if ((routeStateChanged || routeIdentityChanged || headingChanged) &&
        _imageSize != null &&
        widget.autoCenterOnUser) {
      _hasSetInitialRotation = false;
      _setInitialRouteRotation();
      // Recenter after rotation is applied
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final containerSize = box.size;
        _recenterOnUser(containerSize, _imageSize!, initialZoom: 2.0);
      });
    }
  }

  @override
  void dispose() {
    _compassStartTimer?.cancel();
    _compassSubscription?.cancel();
    _rotationTicker.dispose();
    _routeAnimationController.dispose();
    _snapRotationController.dispose();
    if (_ownsTransformController) _transformationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Offset _getUserCoords() {
    // If we are showing a checkpoint floor (not the user's actual physical floor),
    // and we have a route, show the origin of that floor's route segment as a fixed point.
    if (widget.isCheckpoint &&
        widget.route != null &&
        widget.route!.steps.isNotEmpty) {
      return Offset(
        widget.route!.steps.first.from.x,
        widget.route!.steps.first.from.y,
      );
    }

    if (widget.userLocation is LocationEntity) {
      return Offset(widget.userLocation.x, widget.userLocation.y);
    } else if (widget.userLocation is UserPositionEntity) {
      return Offset(widget.userLocation.x, widget.userLocation.y);
    }
    return Offset.zero;
  }

  double _getUserAngle() {
    if (widget.userLocation is LocationEntity) {
      return widget.userLocation.ang ?? 0.0;
    } else if (widget.userLocation is UserPositionEntity) {
      return widget.userLocation.angle;
    }
    return 0.0;
  }

  List<DoorLocationEntity> _uniqueDoorLocations() {
    final seen = <String>{};
    final doors = <DoorLocationEntity>[];

    for (final destination in widget.destinations) {
      final door = destination.doorLocation;
      if (door == null) continue;

      final key = '${door.x.toStringAsFixed(1)}:${door.y.toStringAsFixed(1)}';
      if (seen.add(key)) {
        doors.add(door);
      }
    }

    return doors;
  }

  void _initializeView(Size containerSize, Size imageSize) {
    if (_hasInitializedView || !widget.autoCenterOnUser) return;
    _hasInitializedView = true;
    // Set route rotation first so _recenterOnUser can account for it
    _setInitialRouteRotation();
    _recenterOnUser(containerSize, imageSize, initialZoom: 2.0);
  }

  void _recenterOnUser(
    Size containerSize,
    Size imageSize, {
    double initialZoom = 2.5,
  }) {
    final userPos = _getUserCoords();

    // Scale display image
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = containerSize.width / containerSize.height;

    double displayWidth, displayHeight;
    if (imageAspectRatio > containerAspectRatio) {
      displayWidth = containerSize.width;
      displayHeight = containerSize.width / imageAspectRatio;
    } else {
      displayHeight = containerSize.height;
      displayWidth = containerSize.height * imageAspectRatio;
    }

    final scaleX = displayWidth / imageSize.width;
    final scaleY = displayHeight / imageSize.height;

    // User position in the unrotated display coordinate space
    // (relative to the InteractiveViewer content origin)
    final userDisplayX =
        userPos.dx * scaleX + (containerSize.width - displayWidth) / 2;
    final userDisplayY =
        userPos.dy * scaleY + (containerSize.height - displayHeight) / 2;

    // Transform.rotate rotates around the display center.
    // We must rotate the user point by _manualRotation around that center
    // to find where the user will actually appear on screen.
    final cx = containerSize.width / 2;
    final cy = containerSize.height / 2;
    final dx = userDisplayX - cx;
    final dy = userDisplayY - cy;
    final cosA = math.cos(_manualRotation);
    final sinA = math.sin(_manualRotation);
    final rotatedUserX = cx + dx * cosA - dy * sinA;
    final rotatedUserY = cy + dx * sinA + dy * cosA;

    // Target: horizontally centered, 75% down (Google Maps style)
    final targetX = containerSize.width / 2;
    final targetY = containerSize.height * 0.75;

    final translateX = targetX - rotatedUserX * initialZoom;
    final translateY = targetY - rotatedUserY * initialZoom;

    final newMatrix = Matrix4.identity()
      ..translate(translateX, translateY)
      ..scale(initialZoom);

    _transformationController.value = newMatrix;
    // Save as the initial view to return to when snap button is pressed
    _initialMatrix ??= newMatrix.clone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_hasImageError ||
        (_floorPlanBytes == null && widget.floorPlanBase64.isEmpty)) {
      return _buildErrorView(theme);
    }

    if (_imageSize == null) {
      return Container(
        color: theme.scaffoldBackgroundColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        _initializeView(containerSize, _imageSize!);

        // Auto-recenter zoom after localization (first time)
        if (!_hasRecenteredOnUser && widget.autoCenterOnUser) {
          final userPos = _getUserCoords();
          if (userPos != Offset.zero) {
            _hasRecenteredOnUser = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted)
                _recenterOnUser(containerSize, _imageSize!, initialZoom: 3.5);
            });
          }
        }

        final imageAspectRatio = _imageSize!.width / _imageSize!.height;
        final containerAspectRatio =
            constraints.maxWidth / constraints.maxHeight;

        double displayWidth, displayHeight;
        if (imageAspectRatio > containerAspectRatio) {
          displayWidth = constraints.maxWidth;
          displayHeight = constraints.maxWidth / imageAspectRatio;
        } else {
          displayHeight = constraints.maxHeight;
          displayWidth = constraints.maxHeight * imageAspectRatio;
        }

        final scaleX = displayWidth / _imageSize!.width;
        final scaleY = displayHeight / _imageSize!.height;
        final centerOffsetX = (constraints.maxWidth - displayWidth) / 2;
        final centerOffsetY = (constraints.maxHeight - displayHeight) / 2;

        final userAngle = _getUserAngle();
        final rotationAngle = _manualRotation;

        return Stack(
          children: [
            // Two-finger rotation detector (sits on top, doesn't block IV)
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _activePointers[e.pointer] = e.localPosition;
                if (_activePointers.length == 2) {
                  final pts = _activePointers.values.toList();
                  _lastPointerAngle = math.atan2(
                    pts[1].dy - pts[0].dy,
                    pts[1].dx - pts[0].dx,
                  );
                  _gestureStartAngle = _lastPointerAngle;
                  _isTrackingRotation = true;
                  _rotationThresholdMet = false;
                }
              },
              onPointerMove: (e) {
                _activePointers[e.pointer] = e.localPosition;
                if (_activePointers.length == 2 && _isTrackingRotation) {
                  final pts = _activePointers.values.toList();
                  final newAngle = math.atan2(
                    pts[1].dy - pts[0].dy,
                    pts[1].dx - pts[0].dx,
                  );
                  final delta = newAngle - _lastPointerAngle;

                  // Skip wrap-around jumps
                  if (delta.abs() > 0.3) {
                    _lastPointerAngle = newAngle;
                    return;
                  }

                  // Check if cumulative twist exceeds dead zone threshold
                  if (!_rotationThresholdMet) {
                    final cumulative = (newAngle - _gestureStartAngle).abs();
                    if (cumulative < _rotationThreshold) {
                      _lastPointerAngle = newAngle;
                      return; // still in dead zone — ignore
                    }
                    _rotationThresholdMet = true;
                  }

                  // Apply rotation — filter out tiny noise
                  if (delta.abs() > 0.005) {
                    // Compute user's current screen position BEFORE rotation
                    final userPos = _getUserCoords();
                    final matrix = _transformationController.value;

                    // User position in content (unrotated) space
                    final baseX = userPos.dx * scaleX + centerOffsetX;
                    final baseY = userPos.dy * scaleY + centerOffsetY;

                    // Content center (what Transform.rotate pivots around)
                    final contentCx = constraints.maxWidth / 2;
                    final contentCy = constraints.maxHeight / 2;

                    // Rotate user point by current rotation to get its position
                    // in the InteractiveViewer's coordinate space
                    final cosOld = math.cos(_manualRotation);
                    final sinOld = math.sin(_manualRotation);
                    final dxOld = baseX - contentCx;
                    final dyOld = baseY - contentCy;
                    final userInViewOldX =
                        contentCx + dxOld * cosOld - dyOld * sinOld;
                    final userInViewOldY =
                        contentCy + dxOld * sinOld + dyOld * cosOld;

                    // Same point after new rotation
                    final newRotation = _manualRotation + delta;
                    final cosNew = math.cos(newRotation);
                    final sinNew = math.sin(newRotation);
                    final userInViewNewX =
                        contentCx + dxOld * cosNew - dyOld * sinNew;
                    final userInViewNewY =
                        contentCy + dxOld * sinNew + dyOld * cosNew;

                    // The shift in InteractiveViewer space caused by the rotation
                    final shiftX = userInViewOldX - userInViewNewX;
                    final shiftY = userInViewOldY - userInViewNewY;

                    // Apply rotation and compensate translation atomically
                    final zoom = matrix.getMaxScaleOnAxis();
                    final newMatrix = matrix.clone()
                      ..translate(shiftX / zoom, shiftY / zoom);

                    setState(() => _manualRotation = newRotation);
                    _transformationController.value = newMatrix;
                  }
                  _lastPointerAngle = newAngle;
                }
              },
              onPointerUp: (e) {
                _activePointers.remove(e.pointer);
                if (_activePointers.length < 2) {
                  _isTrackingRotation = false;
                  _rotationThresholdMet = false;
                }
              },
              onPointerCancel: (e) {
                _activePointers.remove(e.pointer);
                if (_activePointers.length < 2) {
                  _isTrackingRotation = false;
                  _rotationThresholdMet = false;
                }
              },
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.1,
                maxScale: 8.0,
                boundaryMargin: const EdgeInsets.all(400),
                child: Transform.rotate(
                  angle: rotationAngle,
                  child: Center(
                    child: SizedBox(
                      width: displayWidth,
                      height: displayHeight,
                      child: Stack(
                        children: [
                          Image.memory(_floorPlanBytes!, fit: BoxFit.fill),

                          // Route Layer
                          if (widget.route != null)
                            AnimatedBuilder(
                              animation: Listenable.merge([
                                _routeAnimationController,
                                getIt<LocationConfigService>().routeColorNotifier,
                              ]),
                              builder: (context, _) => CustomPaint(
                                size: Size(displayWidth, displayHeight),
                                painter: RoutePainter(
                                  coords: widget.route!.steps
                                      .expand(
                                        (s) => [
                                          Offset(s.from.x, s.from.y),
                                          Offset(s.to.x, s.to.y),
                                        ],
                                      )
                                      .toList(),
                                  scaleX: scaleX,
                                  scaleY: scaleY,
                                  animationValue: _routeAnimationController.value,
                                  routeColor: getIt<LocationConfigService>().routeColorNotifier.value,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Debug Info Panel (Same as stable/ar_intrigration)
            ValueListenableBuilder<bool>(
              valueListenable:
                  getIt<LocationConfigService>().debugBannerNotifier,
              builder: (context, showDebug, _) {
                if (!showDebug) return const SizedBox.shrink();

                return Positioned(
                  left: 16,
                  top: 100,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'DEBUG INFO',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'API Ang: ${((widget.route?.steps.isNotEmpty ?? false) ? widget.route!.steps.first.from.ang : null)?.toStringAsFixed(1) ?? "N/A"}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Ref Head: ${widget.capturedReferenceHeading?.toStringAsFixed(1) ?? "N/A"}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Plot Head: ${widget.headingAtStart?.toStringAsFixed(1) ?? "N/A"}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Delta: ${(() {
                              if (widget.headingAtStart == null || widget.capturedReferenceHeading == null) {
                                return "N/A";
                              }
                              double d = widget.headingAtStart! - widget.capturedReferenceHeading!;
                              if (d > 180) d -= 360;
                              if (d < -180) d += 360;
                              return d.toStringAsFixed(1);
                            })()}°',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Map Rot: ${(_manualRotation * 180 / math.pi).toStringAsFixed(1)}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Cur Compass: ${_smoothedHeading.toStringAsFixed(1)}°',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Markers Layer
            AnimatedBuilder(
              animation: Listenable.merge([
                _transformationController,
                getIt<LocationConfigService>().poiColorNotifier,
              ]),
              builder: (context, _) {
                final matrix = _transformationController.value;
                final zoomScale = matrix.getMaxScaleOnAxis();
                final poiColor = getIt<LocationConfigService>().poiColorNotifier.value;

                return Stack(
                  children: [
                    // Doors
                    ..._uniqueDoorLocations().map(
                      (door) => _buildMarker(
                        door.x,
                        door.y,
                        scaleX,
                        scaleY,
                        centerOffsetX,
                        centerOffsetY,
                        zoomScale,
                        rotationAngle,
                        displayWidth,
                        displayHeight,
                        isDoor: true,
                      ),
                    ),

                    // POIs
                    ...widget.destinations.map(
                      (d) => _buildMarker(
                        d.x,
                        d.y,
                        scaleX,
                        scaleY,
                        centerOffsetX,
                        centerOffsetY,
                        zoomScale,
                        rotationAngle,
                        displayWidth,
                        displayHeight,
                        isPOI: true,
                        name: d.name,
                        destination: d,
                        poiColor: poiColor,
                      ),
                    ),

                    // Destination Flag
                    if (widget.route != null && widget.route!.steps.isNotEmpty)
                      _buildMarker(
                        widget.route!.steps.last.to.x,
                        widget.route!.steps.last.to.y,
                        scaleX,
                        scaleY,
                        centerOffsetX,
                        centerOffsetY,
                        zoomScale,
                        rotationAngle,
                        displayWidth,
                        displayHeight,
                        isTarget: true,
                      ),

                    // User
                    _buildMarker(
                      _getUserCoords().dx,
                      _getUserCoords().dy,
                      scaleX,
                      scaleY,
                      centerOffsetX,
                      centerOffsetY,
                      zoomScale,
                      rotationAngle,
                      displayWidth,
                      displayHeight,
                      isUser: true,
                      angle: userAngle,
                      isCheckpoint: widget.isCheckpoint,
                    ),
                  ],
                );
              },
            ),

            if (widget.showControls) ...[
              MapControls(
                right: 16 + widget.mapControlsRightOffset,
                onSearch: () => setState(() => _isSearching = true),
                onReset: () {
                  _hasRecenteredOnUser = false;
                  _recenterOnUser(containerSize, _imageSize!);
                },
                onSnapRotation: () {
                  _snapToInitialRotation();
                  _startCompassTracking(
                    seedHeading: widget.capturedReferenceHeading,
                  );
                },
                isAtInitialRotation:
                    (_manualRotation - _initialRouteRotation).abs() < 0.01,
                onRelocalize: widget.onRelocalize,
              ),

              if (_showLegend)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: _MapLegend(
                    onHide: () => setState(() => _showLegend = false),
                  ),
                ),

              if (!_showLegend)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    onPressed: () => setState(() => _showLegend = true),
                    backgroundColor: theme.colorScheme.surface,
                    child: Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),

              // Palette FAB — opens color picker sheet
              Positioned(
                left: 16,
                bottom: 64,
                child: FloatingActionButton.small(
                  onPressed: () => _showColorPicker(context),
                  backgroundColor: theme.colorScheme.surface,
                  heroTag: 'map_color_picker_fab',
                  child: Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
                ),
              ),

              if (_isSearching)
                MapSearchOverlay(
                  controller: _searchController,
                  filteredDestinations: _filteredDestinations,
                  onClose: () => setState(() => _isSearching = false),
                  onDestinationTap: (d) {
                    setState(() => _isSearching = false);
                    widget.onDestinationTap?.call(d);
                  },
                ),
            ],

            // ── Map Sync Status Indicator ──────────────────────────────────
            ValueListenableBuilder<MapSyncStatus>(
              valueListenable: getIt<MapDownloadService>().syncStatus,
              builder: (context, status, _) {
                if (!status.isSyncing && status.errorMessage == null) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (status.errorMessage != null
                                    ? Colors.red.withValues(alpha: 0.9)
                                    : theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.9))
                                .withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status.isSyncing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white70,
                                ),
                              ),
                            )
                          else
                            Icon(
                              status.errorMessage != null
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            status.isSyncing
                                ? 'Updating maps...'
                                : (status.errorMessage != null
                                      ? 'Map sync failed'
                                      : 'Maps updated'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MapColorPickerSheet(
        config: getIt<LocationConfigService>(),
      ),
    );
  }

  Widget _buildMarker(
    double x,
    double y,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
    double zoom,
    double rotation,
    double displayWidth,
    double displayHeight, {
    bool isUser = false,
    bool isPOI = false,
    bool isTarget = false,
    bool isDoor = false,
    bool isCheckpoint = false,
    double angle = 0.0,
    String? name,
    DestinationEntity? destination,
    Color? poiColor,
  }) {
    final matrix = _transformationController.value;
    final baseX = x * scaleX + offsetX;
    final baseY = y * scaleY + offsetY;

    // To handle rotation, we need to transform the point around the center of the map
    final mapCenter = Offset(
      offsetX + displayWidth / 2,
      offsetY + displayHeight / 2,
    );
    final relativePoint = Offset(baseX, baseY) - mapCenter;

    // Rotate point around map center (CCW convention matches Transform.rotate
    // when rotation values are negated, which is how _manualRotation is stored)
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    final rotatedX = relativePoint.dx * cosR - relativePoint.dy * sinR;
    final rotatedY = relativePoint.dx * sinR + relativePoint.dy * cosR;

    final finalBasePoint = Offset(rotatedX, rotatedY) + mapCenter;

    // Safety check for NaN values which can cause native crashes
    if (finalBasePoint.dx.isNaN ||
        finalBasePoint.dy.isNaN ||
        finalBasePoint.dx.isInfinite ||
        finalBasePoint.dy.isInfinite) {
      return const SizedBox.shrink();
    }

    final pos = MatrixUtils.transformPoint(matrix, finalBasePoint);

    if (pos.dx.isNaN ||
        pos.dy.isNaN ||
        pos.dx.isInfinite ||
        pos.dy.isInfinite) {
      return const SizedBox.shrink();
    }

    if (isUser) {
      final baseSize = isCheckpoint ? 16.0 : 22.0;
      final size = (baseSize * zoom).clamp(4.0, 64.0);
      return Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        child: UserPositionMarker(
          size: size,
          isCheckpoint: isCheckpoint,
          // Compass ON (heading-up): map already rotated so user faces screen-up.
          // Arrow must be 0° — always pointing straight up, never moves.
          // Compass OFF: arrow glued to map rotation (original behaviour).
          orientationDegrees: _compassActive
              ? 0.0
              : (angle + 90) + (rotation * 180 / math.pi),
        ),
      );
    }

    if (isDoor) {
      final size = (9.0 * zoom).clamp(4.0, 22.0);
      return Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        child: DoorLocationMarker(size: size),
      );
    }

    if (isTarget) {
      final size = (18.0 * zoom).clamp(4.0, 56.0);
      return Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        child: DestinationFlagMarker(size: size),
      );
    }

    // POI — selected state is larger so shift the positioning accordingly
    final baseSize = (9.0 * zoom).clamp(1.5, 32.0);
    return Positioned(
      left: pos.dx - baseSize / 2,
      top: pos.dy - baseSize / 2,
      child: DestinationMarker(
        size: baseSize,
        icon: DestinationMarker.getIconForDestination(name ?? ''),
        color: poiColor,
        onTap: destination != null
            ? () {
                setState(() => _selectedDestination = destination);
                widget.onDestinationTap?.call(destination);
              }
            : null,
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text('Error loading floor plan'),
          if (widget.onRetry != null)
            TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  final VoidCallback onHide;
  const _MapLegend({required this.onHide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
        ],
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Legend',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: onHide,
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _LegendItem(
            color: Colors.green,
            icon: Icons.navigation,
            label: 'Your Position',
          ),
          _LegendItem(
            color: const Color(0xFFEA4335),
            icon: Icons.flag,
            label: 'Destination',
          ),
          _LegendItem(
            color: const Color(0xFFEA4335),
            icon: Icons.place,
            label: 'POI / Landmark',
          ),
          _LegendItem(
            color: theme.colorScheme.secondary,
            icon: Icons.meeting_room_outlined,
            label: 'Door Location',
          ),
          _LegendItem(
            color: const Color(0xFF2196F3),
            icon: Icons.horizontal_rule,
            label: 'Route Path',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _LegendItem({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class RoutePainter extends CustomPainter {
  final List<Offset> coords;
  final double scaleX, scaleY;
  final double animationValue;
  final Color routeColor;

  RoutePainter({
    required this.coords,
    required this.scaleX,
    required this.scaleY,
    required this.animationValue,
    this.routeColor = const Color(0xFFFFD600),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.isEmpty) return;

    // Filter out any NaN or Infinity coordinates that could cause native crashes
    final validCoords = coords
        .where(
          (c) =>
              !c.dx.isNaN &&
              !c.dy.isNaN &&
              !c.dx.isInfinite &&
              !c.dy.isInfinite,
        )
        .toList();

    if (validCoords.isEmpty) return;

    final path = Path();
    path.moveTo(validCoords.first.dx * scaleX, validCoords.first.dy * scaleY);

    // Simple smoothing: if a point is too close to previous, skip it
    Offset last = validCoords.first;
    for (var i = 1; i < validCoords.length; i++) {
      final current = validCoords[i];
      if ((current - last).distance > 2.0) {
        path.lineTo(current.dx * scaleX, current.dy * scaleY);
        last = current;
      }
    }

    final pathMetrics = path.computeMetrics().isNotEmpty
        ? path.computeMetrics().first
        : null;
    if (pathMetrics == null) return;

    // 1. White border for contrast
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 3. Main gradient path - segmented for the 'authentic' look
    const segmentCount = 40;
    final pathLength = pathMetrics.length;
    for (int i = 0; i < segmentCount; i++) {
      final start = i / segmentCount;
      final end = (i + 1) / segmentCount;
      final segmentPath = pathMetrics.extractPath(
        start * pathLength,
        end * pathLength,
      );

      final t = i / segmentCount;
      final segmentColor = Color.lerp(
        routeColor,
        Color.lerp(routeColor, Colors.black, 0.35)!,
        t,
      )!;

      canvas.drawPath(
        segmentPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = segmentColor
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // 4. Animated Dashes
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.6);

    const dashLen = 8.0, gapLen = 12.0;
    double dist = (animationValue * 30) % (dashLen + gapLen);
    while (dist < pathLength) {
      canvas.drawPath(pathMetrics.extractPath(dist, dist + dashLen), dashPaint);
      dist += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(RoutePainter old) =>
      old.animationValue != animationValue ||
      old.coords != coords ||
      old.routeColor != routeColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Map Color Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _MapColorPickerSheet extends StatefulWidget {
  final LocationConfigService config;
  const _MapColorPickerSheet({required this.config});

  @override
  State<_MapColorPickerSheet> createState() => _MapColorPickerSheetState();
}

class _MapColorPickerSheetState extends State<_MapColorPickerSheet> {
  static const _routeSwatches = [
    Color(0xFFFFD600), // yellow (default)
    Color(0xFF26C6DA), // teal
    Color(0xFF2196F3), // blue
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFFF44336), // red
    Color(0xFFFF4081), // pink
    Color(0xFF607D8B), // blue-grey
    Color(0xFF00BFA5), // deep teal
  ];

  static const _poiSwatches = [
    Color(0xFF1E88E5), // blue (default)
    Color(0xFFE53935), // red
    Color(0xFF2E7D32), // dark green
    Color(0xFFF57C00), // deep orange
    Color(0xFF6A1B9A), // deep purple
    Color(0xFF00838F), // dark teal
    Color(0xFFF9A825), // amber
    Color(0xFFAD1457), // deep pink
    Color(0xFF37474F), // dark slate
    Color(0xFF558B2F), // olive green
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Map Colors', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),

          // Route color
          _SectionLabel(icon: Icons.route, label: 'Route Path'),
          const SizedBox(height: 10),
          ValueListenableBuilder<Color>(
            valueListenable: widget.config.routeColorNotifier,
            builder: (_, selected, __) => _ColorGrid(
              swatches: _routeSwatches,
              selected: selected,
              onTap: (c) => widget.config.setRouteColor(c),
            ),
          ),

          const SizedBox(height: 22),

          // POI color
          _SectionLabel(icon: Icons.place, label: 'Destination Markers'),
          const SizedBox(height: 10),
          ValueListenableBuilder<Color>(
            valueListenable: widget.config.poiColorNotifier,
            builder: (_, selected, __) => _ColorGrid(
              swatches: _poiSwatches,
              selected: selected,
              onTap: (c) => widget.config.setPoiColor(c),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ColorGrid extends StatelessWidget {
  final List<Color> swatches;
  final Color selected;
  final void Function(Color) onTap;

  const _ColorGrid({required this.swatches, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: swatches.map((c) {
        final isSelected = c.toARGB32() == selected.toARGB32();
        return GestureDetector(
          onTap: () => onTap(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.withValues(alpha: isSelected ? 0.6 : 0.25),
                  blurRadius: isSelected ? 8 : 4,
                  spreadRadius: isSelected ? 1 : 0,
                ),
              ],
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }
}
