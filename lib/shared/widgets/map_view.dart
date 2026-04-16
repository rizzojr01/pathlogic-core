import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fuzzy/fuzzy.dart';

import '../../features/destination/domain/entities/destination_entity.dart';
import '../../features/locate_me/domain/entities/user_position_entity.dart';
import '../../features/navigation/domain/entities/location_entity.dart';
import '../../features/navigation/domain/entities/route_entity.dart';
import '../../injection.dart';
import '../services/map_download_service.dart';
import 'map_controls_widget.dart';
import 'map_markers.dart';
import 'map_search_overlay.dart';

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

  /// Optional: Heading captured at the moment of photo capture (from compass).
  final double? captureHeading;

  const MapView({
    super.key,
    required this.userLocation,
    this.route,
    required this.floorPlanBase64,
    this.destinations = const [],
    this.onDestinationTap,
    this.currentFloor,
    this.isCheckpoint = false,
    this.captureHeading,
    this.onRetry,
    this.onRelocalize,
    this.mapControlsRightOffset = 0,
    this.autoCenterOnUser = true,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  late AnimationController _routeAnimationController;
  final TransformationController _transformationController =
      TransformationController();

  late AnimationController _snapRotationController;
  Animation<double>? _snapRotationAnimation;
  double _manualRotation = 0.0; // radians, current map rotation
  double _initialRouteRotation = 0.0; // radians, set from first route segment
  Matrix4? _initialMatrix; // transformation at initial view

  // Two-pointer rotation tracking
  final Map<int, Offset> _activePointers = {};
  double _lastPointerAngle = 0.0;
  double _gestureStartAngle = 0.0;
  bool _isTrackingRotation = false;
  bool _rotationThresholdMet = false;
  static const double _rotationThreshold = 0.12;

  bool _showLegend = false;
  Uint8List? _floorPlanBytes;
  Size? _imageSize;
  bool _hasImageError = false;
  bool _isSearching = false;
  bool _hasInitializedView = false;
  bool _hasRecenteredOnUser = false;
  bool _hasSetInitialRotation = false;

  // Rotation handling (driven by userLocation.angle externally)
  double _targetRotation = 0.0; // The rotation we want to reach (radians)
  late Ticker _rotationTicker;

  final TextEditingController _searchController = TextEditingController();
  List<DestinationEntity> _filteredDestinations = [];

  @override
  void initState() {
    super.initState();
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

      double diff = _targetRotation - _manualRotation;
      while (diff < -math.pi) {
        diff += 2 * math.pi;
      }
      while (diff > math.pi) {
        diff -= 2 * math.pi;
      }

      // Always snap immediately when driven externally to avoid flickering.
      // The user wants AR to handle rotation, which is high-frequency enough.
      _applyManualRotation(_targetRotation);
    })..start();
  }

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

    final zoom = _transformationController.value.getMaxScaleOnAxis();
    final newMatrix = _transformationController.value.clone()
      ..translate(shiftX / zoom, shiftY / zoom);

    setState(() {
      _manualRotation = newRotation;
      _transformationController.value = newMatrix;
    });
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
                _setInitialRouteRotation();
              });
            }
          }),
        );
  }

  void _setInitialRouteRotation() {
    if (_hasSetInitialRotation) return;
    final route = widget.route;
    if (route == null || route.steps.isEmpty) return;
    _hasSetInitialRotation = true;

    final userAngleDeg = route.steps.first.from.ang ?? 0.0;
    _manualRotation = -(userAngleDeg * math.pi / 180.0 + math.pi / 2);
    _initialRouteRotation = _manualRotation;
    _targetRotation = _manualRotation;
  }

  void _snapToInitialRotation() {
    _snapRotationController.stop();
    final fromRotation = _manualRotation;
    final toRotation = _initialRouteRotation;
    final fromMatrix = _transformationController.value.clone();
    final toMatrix = _initialMatrix ?? _transformationController.value.clone();

    _snapRotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _snapRotationController,
        curve: Curves.easeInOutCubic,
      ),
    )..addListener(() {
        final t = _snapRotationAnimation!.value;
        final newRotation = fromRotation + (toRotation - fromRotation) * t;
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
      setState(() {
        _imageSize = null;
        _hasRecenteredOnUser = false;
        _initialMatrix = null;
        _hasInitializedView = false;
        _hasSetInitialRotation = false;
      });
      _decodeFloorPlan();
    }
    if (oldWidget.destinations != widget.destinations) {
      _filteredDestinations = widget.destinations;
    }

    // ── External Rotation Sync ──────────────────────────────────────────────
    // The map rotation is now purely driven by the angle provided in the
    // userLocation object (which comes from AR tracking).
    final extAngle = _getUserAngle();
    // In Flutter, rotation 0 is East (+X). We want the user's facing direction
    // to point North (Up, -Y).
    final extRotation = -(extAngle * math.pi / 180.0) - (math.pi / 2);
    if ((_targetRotation - extRotation).abs() > 0.001) {
      _targetRotation = extRotation;
    }

    final bool routeStateChanged =
        oldWidget.route == null && widget.route != null;
    final bool routeIdentityChanged =
        oldWidget.route != null &&
        widget.route != null &&
        oldWidget.route!.entityId != widget.route!.entityId;

    if ((routeStateChanged || routeIdentityChanged) && _imageSize != null) {
      _hasSetInitialRotation = false;
      _setInitialRouteRotation();
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
    _rotationTicker.dispose();
    _routeAnimationController.dispose();
    _snapRotationController.dispose();
    _transformationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Offset _getUserCoords() {
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

  void _initializeView(Size containerSize, Size imageSize) {
    if (_hasInitializedView || !widget.autoCenterOnUser) return;
    _hasInitializedView = true;
    _setInitialRouteRotation();
    _recenterOnUser(containerSize, imageSize, initialZoom: 2.0);
  }

  void _recenterOnUser(
    Size containerSize,
    Size imageSize, {
    double initialZoom = 2.5,
  }) {
    final userPos = _getUserCoords();
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
    final userDisplayX =
        userPos.dx * scaleX + (containerSize.width - displayWidth) / 2;
    final userDisplayY =
        userPos.dy * scaleY + (containerSize.height - displayHeight) / 2;

    final cx = containerSize.width / 2;
    final cy = containerSize.height / 2;
    final dx = userDisplayX - cx;
    final dy = userDisplayY - cy;
    final cosA = math.cos(_manualRotation);
    final sinA = math.sin(_manualRotation);
    final rotatedUserX = cx + dx * cosA - dy * sinA;
    final rotatedUserY = cy + dx * sinA + dy * cosA;

    final targetX = containerSize.width / 2;
    final targetY = containerSize.height * 0.75;
    final translateX = targetX - rotatedUserX * initialZoom;
    final translateY = targetY - rotatedUserY * initialZoom;

    final newMatrix = Matrix4.identity()
      ..translate(translateX, translateY)
      ..scale(initialZoom);

    _transformationController.value = newMatrix;
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

        if (!_hasRecenteredOnUser && widget.autoCenterOnUser) {
          final userPos = _getUserCoords();
          if (userPos != Offset.zero) {
            _hasRecenteredOnUser = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _recenterOnUser(containerSize, _imageSize!, initialZoom: 3.5);
              }
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
                  if (delta.abs() > 0.3) {
                    _lastPointerAngle = newAngle;
                    return;
                  }
                  if (!_rotationThresholdMet) {
                    final cumulative = (newAngle - _gestureStartAngle).abs();
                    if (cumulative < _rotationThreshold) {
                      _lastPointerAngle = newAngle;
                      return;
                    }
                    _rotationThresholdMet = true;
                  }

                  if (delta.abs() > 0.005) {
                    final userPos = _getUserCoords();
                    final matrix = _transformationController.value;
                    final baseX = userPos.dx * scaleX + centerOffsetX;
                    final baseY = userPos.dy * scaleY + centerOffsetY;
                    final contentCx = constraints.maxWidth / 2;
                    final contentCy = constraints.maxHeight / 2;
                    final cosOld = math.cos(_manualRotation);
                    final sinOld = math.sin(_manualRotation);
                    final dxOld = baseX - contentCx;
                    final dyOld = baseY - contentCy;
                    final uOldX = contentCx + dxOld * cosOld - dyOld * sinOld;
                    final uOldY = contentCy + dxOld * sinOld + dyOld * cosOld;
                    final newRotation = _manualRotation + delta;
                    final cosNew = math.cos(newRotation);
                    final sinNew = math.sin(newRotation);
                    final uNewX = contentCx + dxOld * cosNew - dyOld * sinNew;
                    final uNewY = contentCy + dxOld * sinNew + dyOld * cosNew;
                    final zoom = matrix.getMaxScaleOnAxis();
                    final newMatrix = matrix.clone()
                      ..translate((uOldX - uNewX) / zoom, (uOldY - uNewY) / zoom);
                    setState(() => _manualRotation = newRotation);
                    _transformationController.value = newMatrix;
                  }
                  _lastPointerAngle = newAngle;
                }
              },
              onPointerUp: (e) => _activePointers.remove(e.pointer),
              onPointerCancel: (e) => _activePointers.remove(e.pointer),
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
                          if (widget.route != null)
                            AnimatedBuilder(
                              animation: _routeAnimationController,
                              builder: (context, _) => CustomPaint(
                                size: Size(displayWidth, displayHeight),
                                painter: RoutePainter(
                                  coords: widget.route!.steps
                                      .expand((s) => [Offset(s.from.x, s.from.y), Offset(s.to.x, s.to.y)])
                                      .toList(),
                                  scaleX: scaleX,
                                  scaleY: scaleY,
                                  animationValue: _routeAnimationController.value,
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
            AnimatedBuilder(
              animation: _transformationController,
              builder: (context, _) {
                final matrix = _transformationController.value;
                final zoomScale = matrix.getMaxScaleOnAxis();
                return Stack(
                  children: [
                    ...widget.destinations.map((d) => _buildMarker(d.x, d.y, scaleX, scaleY, centerOffsetX, centerOffsetY, zoomScale, rotationAngle, displayWidth, displayHeight, isPOI: true, name: d.name, destination: d)),
                    if (widget.route != null && widget.route!.steps.isNotEmpty)
                      _buildMarker(widget.route!.steps.last.to.x, widget.route!.steps.last.to.y, scaleX, scaleY, centerOffsetX, centerOffsetY, zoomScale, rotationAngle, displayWidth, displayHeight, isTarget: true),
                    _buildMarker(_getUserCoords().dx, _getUserCoords().dy, scaleX, scaleY, centerOffsetX, centerOffsetY, zoomScale, rotationAngle, displayWidth, displayHeight, isUser: true, angle: userAngle, isCheckpoint: widget.isCheckpoint),
                  ],
                );
              },
            ),
            MapControls(
              right: 16 + widget.mapControlsRightOffset,
              onSearch: () => setState(() => _isSearching = true),
              onReset: () {
                _hasRecenteredOnUser = false;
                _recenterOnUser(containerSize, _imageSize!);
              },
              onSnapRotation: _snapToInitialRotation,
              isAtInitialRotation: (_manualRotation - _initialRouteRotation).abs() < 0.01,
              onRelocalize: widget.onRelocalize,
            ),
            if (_showLegend) Positioned(left: 16, bottom: 16, child: _MapLegend(onHide: () => setState(() => _showLegend = false)))
            else Positioned(left: 16, bottom: 16, child: FloatingActionButton.small(onPressed: () => setState(() => _showLegend = true), backgroundColor: theme.colorScheme.surface, child: Icon(Icons.info_outline, color: theme.colorScheme.primary))),
            if (_isSearching) MapSearchOverlay(controller: _searchController, filteredDestinations: _filteredDestinations, onClose: () => setState(() => _isSearching = false), onDestinationTap: (d) { setState(() => _isSearching = false); widget.onDestinationTap?.call(d); }),
            ValueListenableBuilder<MapSyncStatus>(
              valueListenable: getIt<MapDownloadService>().syncStatus,
              builder: (context, status, _) {
                if (!status.isSyncing && status.errorMessage == null) return const SizedBox.shrink();
                return Positioned(
                  top: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: (status.errorMessage != null ? Colors.red : theme.colorScheme.primaryContainer).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status.isSyncing) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white70)))
                          else Icon(status.errorMessage != null ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: theme.colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text(status.isSyncing ? 'Updating maps...' : (status.errorMessage != null ? 'Map sync failed' : 'Maps updated'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
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

  Widget _buildMarker(double x, double y, double sX, double sY, double offX, double offY, double zoom, double rot, double dW, double dH, {bool isUser = false, bool isPOI = false, bool isTarget = false, bool isCheckpoint = false, double angle = 0.0, String? name, DestinationEntity? destination}) {
    final matrix = _transformationController.value;
    final baseX = x * sX + offX;
    final baseY = y * sY + offY;
    final mapCenter = Offset(offX + dW / 2, offY + dH / 2);
    final relative = Offset(baseX, baseY) - mapCenter;
    final cosR = math.cos(rot), sinR = math.sin(rot);
    final finalBase = Offset(relative.dx * cosR - relative.dy * sinR, relative.dx * sinR + relative.dy * cosR) + mapCenter;
    if (finalBase.dx.isNaN || finalBase.dy.isNaN) return const SizedBox.shrink();
    final pos = MatrixUtils.transformPoint(matrix, finalBase);
    if (isUser) {
      final size = ((isCheckpoint ? 16.0 : 22.0) * zoom).clamp(4.0, 64.0);
      return Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        child: UserPositionMarker(
          size: size,
          isCheckpoint: isCheckpoint,
          // Since the map is now rotating "Heading-Up", the arrow
          // should always point straight up (0 degrees on screen).
          orientationDegrees: 0,
        ),
      );
    }
    if (isTarget) {
      final size = (18.0 * zoom).clamp(4.0, 56.0);
      return Positioned(left: pos.dx - size / 2, top: pos.dy - size / 2, child: DestinationFlagMarker(size: size));
    }
    final size = (12.0 * zoom).clamp(1.5, 40.0);
    return Positioned(left: pos.dx - size / 2, top: pos.dy - size / 2, child: DestinationMarker(size: size, icon: DestinationMarker.getIconForDestination(name ?? ''), onTap: destination != null ? () => widget.onDestinationTap?.call(destination) : null));
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, size: 48, color: Colors.red), const SizedBox(height: 16), const Text('Error loading floor plan'), if (widget.onRetry != null) TextButton(onPressed: widget.onRetry, child: const Text('Retry'))]));
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
      decoration: BoxDecoration(color: theme.colorScheme.surface.withOpacity(0.9), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)], border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Legend', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)), IconButton(onPressed: onHide, icon: const Icon(Icons.close, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints())]),
          const SizedBox(height: 8),
          _LegendItem(color: Colors.green, icon: Icons.navigation, label: 'Your Position'),
          _LegendItem(color: const Color(0xFFEA4335), icon: Icons.flag, label: 'Destination'),
          _LegendItem(color: const Color(0xFFEA4335), icon: Icons.place, label: 'POI / Landmark'),
          _LegendItem(color: const Color(0xFF2196F3), icon: Icons.horizontal_rule, label: 'Route Path'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color; final IconData icon; final String label;
  const _LegendItem({required this.color, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 16), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 12))])); }
}

class RoutePainter extends CustomPainter {
  final List<Offset> coords; final double scaleX, scaleY; final double animationValue;
  RoutePainter({required this.coords, required this.scaleX, required this.scaleY, required this.animationValue});
  @override
  void paint(Canvas canvas, Size size) {
    if (coords.isEmpty) return;
    final validCoords = coords.where((c) => !c.dx.isNaN && !c.dy.isNaN).toList();
    if (validCoords.isEmpty) return;
    final path = Path();
    path.moveTo(validCoords.first.dx * scaleX, validCoords.first.dy * scaleY);
    Offset last = validCoords.first;
    for (var i = 1; i < validCoords.length; i++) {
      final current = validCoords[i];
      if ((current - last).distance > 2.0) { path.lineTo(current.dx * scaleX, current.dy * scaleY); last = current; }
    }
    final pathMetrics = path.computeMetrics().isNotEmpty ? path.computeMetrics().first : null;
    if (pathMetrics == null) return;
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 14..color = const Color(0xFF4FC3F7).withOpacity(0.15)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = Colors.white..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    const segmentCount = 40;
    final pathLength = pathMetrics.length;
    for (int i = 0; i < segmentCount; i++) {
      final start = i / segmentCount; final end = (i + 1) / segmentCount;
      final segmentPath = pathMetrics.extractPath(start * pathLength, end * pathLength);
      final t = i / segmentCount;
      final segmentColor = Color.lerp(const Color(0xFF4FC3F7), const Color(0xFF2196F3), t)!;
      canvas.drawPath(segmentPath, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = segmentColor..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    }
    final dashPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..color = Colors.white.withOpacity(0.6);
    const dashLen = 8.0, gapLen = 12.0;
    double dist = (animationValue * 30) % (dashLen + gapLen);
    while (dist < pathLength) { canvas.drawPath(pathMetrics.extractPath(dist, dist + dashLen), dashPaint); dist += dashLen + gapLen; }
  }
  @override
  bool shouldRepaint(RoutePainter old) => old.animationValue != animationValue || old.coords != coords;
}
