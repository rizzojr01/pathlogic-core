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
// Shows the full floor plan with complete route — static, no interaction.
// "Start Navigation" passes the existing bloc to NavigationPage (no re-fetch).
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

  Future<void> _startNavigation() async {
    // Capture the compass heading NOW — this is the correct "start of navigation"
    // heading for route orientation, not the one captured during overview init.
    double? freshHeading;
    try {
      final event = await FlutterCompass.events?.first.timeout(
        const Duration(milliseconds: 600),
      );
      freshHeading = event?.heading;
    } catch (_) {}

    if (!mounted) return;
    final bloc = context.read<NavigationBloc>();
    context.pushReplacement(
      '/navigation',
      extra: {
        'destination': widget.destination,
        'imagePath': widget.imagePath,
        'manualCoordinates': widget.userPickedCoordinates,
        'pickedFloor': widget.pickedFloor,
        'heading': widget.heading,
        'existingBloc': bloc,
        'freshHeadingAtStart': freshHeading,
      },
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
              onStart: _startNavigation,
              onBack: () => context.pop(),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview Content
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewContent extends StatelessWidget {
  final DestinationEntity destination;
  final NavigationReady state;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const _OverviewContent({
    required this.destination,
    required this.state,
    required this.onStart,
    required this.onBack,
  });

  String _normaliseFloor(String f) =>
      f.replaceAll('_floor', '').replaceAll('_', '').trim().toLowerCase();

  RouteEntity _routeForFloor(String floor) {
    final steps = state.route.multiFloorSteps
        .where((f) => f.floor == floor)
        .toList();
    return RouteEntity(
      entityId: state.route.entityId,
      multiFloorSteps: steps,
    );
  }

  List<DestinationEntity> _destsForFloor(String floor) {
    final norm = _normaliseFloor(floor);
    final all = [
      ...state.destinationsByFloor.values.expand((l) => l),
      ...state.destinations,
    ];
    return all
        .where((d) => d.floor == null || _normaliseFloor(d.floor!) == norm)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final floor = state.route.multiFloorSteps.isNotEmpty
        ? state.route.multiFloorSteps.first.floor
        : 'unknown';
    final floorPlan =
        state.floorPlansByFloor[floor] ?? state.floorPlanBase64 ?? '';
    final route = _routeForFloor(floor);
    final dests = _destsForFloor(floor);

    return SafeArea(
      child: Column(
        children: [
          // ── Top bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: onBack,
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

          // ── Static map (exact MapView, no interaction, no controls) ───
          Expanded(
            child: AbsorbPointer(
              child: MapView(
                userLocation: state.currentLocation,
                route: route,
                floorPlanBase64: floorPlan,
                destinations: dests,
                currentFloor: state.currentLocation.floor,
                autoCenterOnUser: false,
                showControls: false,
                headingAtStart: state.headingAtStart,
                capturedReferenceHeading: state.capturedReferenceHeading,
              ),
            ),
          ),

          // ── Destination card + Start button ───────────────────────────
          _DestinationCard(
            destination: destination,
            route: route,
            onStart: onStart,
          ),
        ],
      ),
    );
  }
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
