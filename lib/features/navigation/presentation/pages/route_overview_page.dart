import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/custom_error_view.dart';
import '../../../../shared/widgets/custom_loading_view.dart';
import '../../../../shared/widgets/map_view.dart';
import '../../../destination/domain/entities/destination_entity.dart';
import '../../domain/entities/route_entity.dart';
import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_event.dart';
import '../bloc/navigation_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route Overview Page
// ─────────────────────────────────────────────────────────────────────────────

class RouteOverviewPage extends StatefulWidget {
  final DestinationEntity destination;
  final String? imagePath;
  final Map<String, dynamic>? userPickedCoordinates;
  final String? pickedFloor;
  final double? heading;

  const RouteOverviewPage({
    super.key,
    required this.destination,
    this.imagePath,
    this.userPickedCoordinates,
    this.pickedFloor,
    this.heading,
  });

  @override
  State<RouteOverviewPage> createState() => _RouteOverviewPageState();
}

class _RouteOverviewPageState extends State<RouteOverviewPage> {
  @override
  void initState() {
    super.initState();
    context.read<NavigationBloc>().add(
      InitializeNavigationEvent(
        widget.destination,
        imagePath: widget.imagePath,
        userPickedCoordinates: widget.userPickedCoordinates,
        pickedFloor: widget.pickedFloor,
        heading: widget.heading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: BlocBuilder<NavigationBloc, NavigationState>(
        builder: (context, state) {
          if (state is NavigationInitial || state is NavigationLoading) {
            return const CustomLoadingView(message: 'Calculating route...');
          }
          if (state is NavigationError) {
            return CustomErrorView(
              message: state.message,
              onRetry: () => context.read<NavigationBloc>().add(
                InitializeNavigationEvent(
                  widget.destination,
                  imagePath: widget.imagePath,
                  userPickedCoordinates: widget.userPickedCoordinates,
                  pickedFloor: widget.pickedFloor,
                  heading: widget.heading,
                ),
              ),
              onExit: () => context.pop(),
            );
          }
          if (state is NavigationReady) {
            return _OverviewContent(
              destination: widget.destination,
              state: state,
              imagePath: widget.imagePath,
              userPickedCoordinates: widget.userPickedCoordinates,
              pickedFloor: widget.pickedFloor,
              capturedHeading: widget.heading,
              onBack: () {
                context.read<NavigationBloc>().close();
                context.pop();
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview Content — owns the map controller and drives the zoom-in animation
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewContent extends StatefulWidget {
  final DestinationEntity destination;
  final NavigationReady state;
  final String? imagePath;
  final Map<String, dynamic>? userPickedCoordinates;
  final String? pickedFloor;
  final double? capturedHeading;
  final VoidCallback onBack;

  const _OverviewContent({
    required this.destination,
    required this.state,
    required this.onBack,
    this.imagePath,
    this.userPickedCoordinates,
    this.pickedFloor,
    this.capturedHeading,
  });

  @override
  State<_OverviewContent> createState() => _OverviewContentState();
}

class _OverviewContentState extends State<_OverviewContent>
    with SingleTickerProviderStateMixin {
  // Externally-controlled map transformation (animated on "Start Navigation")
  final TransformationController _mapController = TransformationController();
  late AnimationController _zoomController;

  bool _animating = false;
  Size? _imageSize;
  Size? _containerSize;

  late String _floor;
  late String _floorPlan;
  late RouteEntity _route;
  late List<DestinationEntity> _dests;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _initFloorData();
    _loadImageSize();
  }

  void _initFloorData() {
    _floor = widget.state.route.multiFloorSteps.isNotEmpty
        ? widget.state.route.multiFloorSteps.first.floor
        : 'unknown';
    _floorPlan =
        widget.state.floorPlansByFloor[_floor] ??
        widget.state.floorPlanBase64 ??
        '';
    _route = _routeForFloor(_floor);
    _dests = _destsForFloor(_floor);
  }

  void _loadImageSize() {
    if (_floorPlan.isEmpty) return;
    try {
      final bytes = base64Decode(_floorPlan);
      final image = MemoryImage(bytes);
      image.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((info, _) {
          if (mounted) {
            setState(() => _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            ));
          }
        }),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _mapController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  String _normalise(String f) =>
      f.replaceAll('_floor', '').replaceAll('_', '').trim().toLowerCase();

  RouteEntity _routeForFloor(String floor) {
    final steps = widget.state.route.multiFloorSteps
        .where((f) => f.floor == floor)
        .toList();
    return RouteEntity(
      entityId: widget.state.route.entityId,
      multiFloorSteps: steps,
    );
  }

  List<DestinationEntity> _destsForFloor(String floor) {
    final norm = _normalise(floor);
    final all = [
      ...widget.state.destinationsByFloor.values.expand((l) => l),
      ...widget.state.destinations,
    ];
    return all
        .where((d) => d.floor == null || _normalise(d.floor!) == norm)
        .toSet()
        .toList();
  }

  /// Computes the InteractiveViewer matrix that centers the user on screen at
  /// [zoom]× magnification — matches MapView's own _recenterOnUser logic.
  Matrix4? _userCenteredMatrix({double zoom = 2.5}) {
    final c = _containerSize;
    final img = _imageSize;
    if (c == null || img == null) return null;

    final iAR = img.width / img.height;
    final cAR = c.width / c.height;
    double dispW, dispH;
    if (iAR > cAR) {
      dispW = c.width;
      dispH = c.width / iAR;
    } else {
      dispH = c.height;
      dispW = c.height * iAR;
    }
    final sX = dispW / img.width;
    final sY = dispH / img.height;
    final offX = (c.width - dispW) / 2;
    final offY = (c.height - dispH) / 2;

    final userX = widget.state.currentLocation.x * sX + offX;
    final userY = widget.state.currentLocation.y * sY + offY;

    // Same target position as MapView._recenterOnUser (75% down, horizontally centred)
    final tx = c.width / 2 - userX * zoom;
    final ty = c.height * 0.75 - userY * zoom;

    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(zoom);
  }

  Future<void> _startNavigation() async {
    if (_animating) return;
    setState(() => _animating = true);

    // Capture compass heading at tap-time (correct "start navigation" heading)
    double? freshHeading;
    try {
      final event = await FlutterCompass.events?.first.timeout(
        const Duration(milliseconds: 500),
      );
      freshHeading = event?.heading;
    } catch (_) {}

    if (!mounted) return;

    // Animate the map from full-route overview → user-centred zoom
    final target = _userCenteredMatrix();
    if (target != null) {
      final fromStorage = _mapController.value.storage.toList();
      final toStorage = target.storage;
      final anim = CurvedAnimation(
        parent: _zoomController,
        curve: Curves.easeInOutCubic,
      );
      anim.addListener(() {
        final t = anim.value;
        _mapController.value = Matrix4.fromList(
          List.generate(16, (i) => fromStorage[i] + (toStorage[i] - fromStorage[i]) * t),
        );
      });
      _zoomController.forward(from: 0);

      // Let the zoom run for a bit so the user sees motion before the page fades
      await Future.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
    }

    // Same NavigationBloc singleton is wired into /navigation via the
    // router (BlocProvider.value), so we no longer need to pass the bloc
    // through `extra`. `skipInitialization: true` tells NavigationPage
    // the bloc already holds the route — don't re-fetch.
    context.pushReplacement(
      '/navigation',
      extra: {
        'destination': widget.destination,
        'imagePath': widget.imagePath,
        'manualCoordinates': widget.userPickedCoordinates,
        'pickedFloor': widget.pickedFloor,
        'heading': widget.capturedHeading,
        'skipInitialization': true,
        'freshHeadingAtStart': freshHeading,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Store container size for matrix computation (exclude card)
          final mapHeight = constraints.maxHeight - _cardApproxHeight;
          final mapSize = Size(constraints.maxWidth, mapHeight.clamp(100.0, double.infinity));
          if (_containerSize != mapSize) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) { if (mounted) setState(() => _containerSize = mapSize); },
            );
          }

          return Column(
            children: [
              // ── Top bar ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: widget.onBack,
                    ),
                    Expanded(
                      child: Text(
                        'Route Overview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Static map (interactive locked, same visual as nav map) ──
              Expanded(
                child: AbsorbPointer(
                  child: MapView(
                    userLocation: widget.state.currentLocation,
                    route: _route,
                    floorPlanBase64: _floorPlan,
                    destinations: _dests,
                    currentFloor: widget.state.currentLocation.floor,
                    autoCenterOnUser: false,
                    showControls: false,
                    headingAtStart: widget.state.headingAtStart,
                    capturedReferenceHeading: widget.state.capturedReferenceHeading,
                    externalTransformController: _mapController,
                  ),
                ),
              ),

              // ── Destination card — slides down when animation starts ──────
              AnimatedSlide(
                offset: _animating ? const Offset(0, 1) : Offset.zero,
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeInCubic,
                child: AnimatedOpacity(
                  opacity: _animating ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: _DestinationCard(
                    destination: widget.destination,
                    route: _route,
                    onStart: _startNavigation,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Approximate height of the card so the map container size is correct
  static const double _cardApproxHeight = 180.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Destination card + Start button
// ─────────────────────────────────────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  final DestinationEntity destination;
  final RouteEntity route;
  final VoidCallback onStart;

  const _DestinationCard({
    required this.destination,
    required this.route,
    required this.onStart,
  });

  String get _floorLabel {
    final f = destination.floor ?? '';
    return f.replaceAll('_floor', '').replaceAll('_', ' ').trim();
  }

  String get _stepsLabel {
    final n = route.steps.length;
    return '$n waypoint${n == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.place_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (_floorLabel.isNotEmpty) _floorLabel, _stepsLabel]
                          .join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.navigation_rounded, size: 20),
            label: const Text(
              'Start Navigation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
