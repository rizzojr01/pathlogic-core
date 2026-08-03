import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import '../../core/services/speech_service.dart';
import '../../routes/app_router.dart';

import '../../core/utils/logger.dart';
import '../../core/error/failures.dart';

import '../../features/destination/presentation/bloc/floor_map_bloc.dart';
import '../../features/destination/presentation/bloc/floor_map_event.dart';
import '../../features/destination/presentation/bloc/floor_map_state.dart';

import '../../injection.dart';
import '../services/location_config_service.dart';
import 'custom_snackbar.dart' as snackbar;
import 'floor_plan_selector_widget.dart';

class LocationInputView extends StatefulWidget {
  final TabController tabController;
  final Function(String path, String floor, double? heading) onImageCaptured;
  final Function(double x, double y, String floor) onLocationSelected;
  final String floorPlanConfirmText;
  final String? initialFloor;

  const LocationInputView({
    super.key,
    required this.tabController,
    required this.onImageCaptured,
    required this.onLocationSelected,
    this.floorPlanConfirmText = 'Set My Location',
    this.initialFloor,
  });

  @override
  State<LocationInputView> createState() => _LocationInputViewState();
}

class _LocationInputViewState extends State<LocationInputView> with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  CameraController? _controller;
  CameraMacOSController? _macOSController;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _showGuidance = true;
  String? _errorMessage;

  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _currentHeading;
  final _logger = getIt<AppLogger>();

  late FloorMapBloc _floorMapBloc;
  FixedExtentScrollController? _floorController;

  late AnimationController _pulseController;
  Timer? _guidanceTimer;
  bool _showRevisedGuidance = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeCompass();
    _floorMapBloc = FloorMapBloc()
      ..add(FloorMapInitialized(initialFloor: widget.initialFloor));

    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _startGuidanceTimer();
    
    // Audio feedback: Select destination
    getIt<SpeechService>().speak("Please capture a photo to find your location.");
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppRouter.routeObserver.subscribe(this, ModalRoute.of(context) as ModalRoute<void>);
  }

  void _startGuidanceTimer() {
    _guidanceTimer?.cancel();
    _guidanceTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.tabController.index == 0) {
        setState(() => _showRevisedGuidance = true);
        getIt<SpeechService>().speak("Tap the capture button at the bottom to find your location.");
      }
    });
  }

  void _initializeCompass() {
    try {
      _compassSubscription = FlutterCompass.events?.listen((event) {
        if (mounted) {
          setState(() {
            _currentHeading = event.heading;
          });
        }
      });
    } catch (e) {
      _logger.error('Error initializing compass: $e');
    }
  }

  void _syncFloorController(List<String> floors, String selectedFloor) {
    if (floors.isEmpty) return;
    final index = floors.indexOf(selectedFloor);
    if (index >= 0) {
      if (_floorController == null) {
        _floorController = FixedExtentScrollController(initialItem: index);
      } else if (_floorController!.hasClients &&
          _floorController!.selectedItem != index) {
        _floorController!.jumpToItem(index);
      }
    }
  }

  @override
  void dispose() {
    AppRouter.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null; // Important: nullify after dispose
    _floorController?.dispose();
    _compassSubscription?.cancel();
    _floorMapBloc.close();
    _pulseController.dispose();
    _guidanceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Set _isInitializing to true to hide the preview in the UI
      if (mounted) setState(() => _isInitializing = true);
      cameraController.dispose();
      _controller = null; // Important: nullify after dispose
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  void didPushNext() {
    // Called when a new route is pushed and the current route is no longer visible
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }
    if (mounted) setState(() => _isInitializing = true);
  }

  @override
  void didPopNext() {
    // Called when the top route has been popped off, and the current route shows up
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _isInitializing = true;
        });
      }

      // Small delay to allow previous camera controllers (e.g. from NavigationPage)
      // to fully release hardware resources before we try to take them.
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      if ((!kIsWeb && Platform.isMacOS)) {
        if (mounted) setState(() => _errorMessage = null);
        return;
      }

      // Dispose old controller if it exists
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'No cameras found on this device.';
          });
        }
        return;
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      // Add timeout to prevent hanging indefinitely
      await _controller!.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Camera initialization timed out'),
      );
      
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = Failure.sanitize('Error initializing camera: $e');
        });
      }
    }
  }

  Future<bool> _isImageClear(String path) async {
    // Placeholder for image quality check (focus/blur/motion)
    // In a production app, we would use a native plugin or TFLite model
    // to check Laplacian variance or similar metrics.
    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // Simulate processing
    return true; // Auto-accepting for now
  }

  Future<void> _captureImage() async {
    if ((!kIsWeb && Platform.isMacOS)) {
      if (_macOSController != null && !_isCapturing) {
        setState(() => _isCapturing = true);
        final headingAtCapture = _currentHeading;
        try {
          final result = await _macOSController!.takePicture();
          if (result != null && result.bytes != null) {
            final tempDir = await getTemporaryDirectory();
            final file = File(
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            await file.writeAsBytes(result.bytes!);

            final isClear = await _isImageClear(file.path);
            if (mounted) {
              if (isClear) {
                String selectedFloor = getIt<LocationConfigService>().floor;
                if (_floorMapBloc.state is FloorMapReady) {
                  selectedFloor =
                      (_floorMapBloc.state as FloorMapReady).selectedFloor;
                }
                _logger.info(
                  'Image Captured with Heading: ${headingAtCapture?.toStringAsFixed(2)}°',
                );
                widget.onImageCaptured(
                  file.path,
                  selectedFloor,
                  headingAtCapture,
                );
              } else {
                snackbar.CustomSnackBar.show(
                  context,
                  message: 'Image is blurry. Please hold steady and try again.',
                  type: snackbar.SnackBarType.warning,
                );
              }
            }
          }
        } catch (e) {
          if (mounted) {
            snackbar.CustomSnackBar.show(
              context,
              message: Failure.sanitize('Failed to capture image: ${e.toString()}'),
              type: snackbar.SnackBarType.error,
            );
          }
        } finally {
          if (mounted) setState(() => _isCapturing = false);
        }
      }
      return;
    }

    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

  setState(() {
      _isCapturing = true;
      _showRevisedGuidance = false;
    });
    _guidanceTimer?.cancel();
    getIt<SpeechService>().speak("Capturing photo...");

    try {
      // 1. Capture the heading IMMEDIATELY
      final capturedHeading = _currentHeading;

      // 2. Take the picture
      final image = await _controller!.takePicture();

      // Ensure the file is fully written before reading (skip on web — XFile
      // wraps a blob URL, dart:io File has no web impl).
      if (!kIsWeb) {
        final imageFile = File(image.path);
        int retryCount = 0;
        while (!await imageFile.exists() && retryCount < 5) {
          await Future.delayed(const Duration(milliseconds: 100));
          retryCount++;
        }
      }

      final isClear = await _isImageClear(image.path);

      if (mounted) {
        if (isClear) {
          String selectedFloor = getIt<LocationConfigService>().floor;
          if (_floorMapBloc.state is FloorMapReady) {
            selectedFloor =
                (_floorMapBloc.state as FloorMapReady).selectedFloor;
          }
          _logger.info(
            'Image Captured with Heading: ${capturedHeading?.toStringAsFixed(2)}°',
          );
          widget.onImageCaptured(image.path, selectedFloor, capturedHeading);
        } else {
          snackbar.CustomSnackBar.show(
            context,
            message: 'Image is blurry. Please hold steady and try again.',
            type: snackbar.SnackBarType.warning,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        snackbar.CustomSnackBar.show(
          context,
          message: Failure.sanitize('Failed to capture image: ${e.toString()}'),
          type: snackbar.SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TabBarView(
      controller: widget.tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [_buildCameraTab(theme), _buildFloorPlanTab(theme)],
    );
  }

  Widget _buildCameraTab(ThemeData theme) {
    // macOS Camera View
    if ((!kIsWeb && Platform.isMacOS)) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CameraMacOSView(
            key: GlobalKey(),
            fit: BoxFit.cover,
            cameraMode: CameraMacOSMode.photo,
            onCameraInizialized: (CameraMacOSController controller) {
              if (mounted) {
                setState(() {
                  _macOSController = controller;
                  _isInitializing = false;
                  _errorMessage = null; // Clear any previous error
                });
              }
            },
          ),
          if (_isInitializing) const Center(child: CircularProgressIndicator()),
          if (!_isInitializing) ...[
            _CameraGuidance(
              showGuidance: _showGuidance,
              onToggle: () => setState(() => _showGuidance = !_showGuidance),
            ),
            // Capture Button (Shared UI)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(width: 60), // Spacer for symmetry
                  _buildCaptureButton(theme),
                  const SizedBox(width: 60), // Spacer for symmetry
                ],
              ),
            ),
          ],
        ],
      );
    }

    // Mobile Camera View
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Camera not available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isInitializing = true);
                  _initializeCamera();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Camera Preview (fullscreen)
        Positioned.fill(child: CameraPreview(_controller!)),

        // 2. Camera Guidance Overlays (CEILING, PATH, FLOOR)
        _CameraGuidance(
          showGuidance: _showGuidance,
          onToggle: () => setState(() => _showGuidance = !_showGuidance),
        ),

        // 3. Guidance Overlay (Dark bottom area)
        if (_showRevisedGuidance)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

        // 4. Capture Button & Arrow
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showRevisedGuidance) ...[
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      const Text(
                        'Tap to find yourself',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(width: 60), // Spacer for symmetry
                  _buildCaptureButton(theme),
                  const SizedBox(width: 60), // Spacer for symmetry
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureButton(ThemeData theme) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return GestureDetector(
          onTap: _captureImage,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: 0.4 + (0.2 * _pulseController.value),
                  ),
                  blurRadius: 15 + (15 * _pulseController.value),
                  spreadRadius: 2 + (4 * _pulseController.value),
                ),
              ],
            ),
            child: _isCapturing
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Icon(
                    Icons.camera_rounded,
                    color: theme.colorScheme.onPrimary,
                    size: 40,
                  ),
          ),
        );
      },
    );
  }


  Widget _buildFloorPlanTab(ThemeData theme) {
    final locationConfig = getIt<LocationConfigService>();

    return BlocProvider.value(
      value: _floorMapBloc,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BlocListener<FloorMapBloc, FloorMapState>(
          listener: (context, state) {
            if (state is FloorMapReady) {
              _syncFloorController(state.availableFloors, state.selectedFloor);
            }
          },
          child: Stack(
            children: [
              BlocBuilder<FloorMapBloc, FloorMapState>(
                builder: (context, state) {
                  if (state is FloorMapLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is FloorMapReady) {
                    return FloorPlanSelectorWidget(
                      base64FloorPlan: state.base64FloorPlan,
                      destinations: state.destinations,
                      onLocationSelected: (x, y) =>
                          widget.onLocationSelected(x, y, state.selectedFloor),
                      confirmButtonText: widget.floorPlanConfirmText,
                    );
                  } else if (state is FloorMapError) {
                    return Center(
                      child: Text(
                        'Error: ${state.message}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Rotary Floor Selector (Integrated into the tab)
              if (locationConfig.multiFloorNavigation)
                BlocBuilder<FloorMapBloc, FloorMapState>(
                  builder: (context, state) {
                    if (state is FloorMapReady &&
                        state.availableFloors.isNotEmpty) {
                      _syncFloorController(
                        state.availableFloors,
                        state.selectedFloor,
                      );

                      return Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                width: 44,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(
                                    0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    CupertinoPicker(
                                      scrollController: _floorController,
                                      itemExtent: 34,
                                      diameterRatio: 0.9,
                                      squeeze: 1.3,
                                      magnification: 1.1,
                                      useMagnifier: true,
                                      onSelectedItemChanged: (index) {
                                        HapticFeedback.selectionClick();
                                        final newFloor =
                                            state.availableFloors[index];
                                        if (newFloor != state.selectedFloor) {
                                          _floorMapBloc.add(
                                            FloorMapFloorChanged(newFloor),
                                          );
                                        }
                                      },
                                      children: state.availableFloors
                                          .map(
                                            (f) => Center(
                                              child: Text(
                                                f.replaceAll(
                                                  RegExp(r'[^0-9]'),
                                                  '',
                                                ),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraGuidance extends StatefulWidget {
  final bool showGuidance;
  final VoidCallback onToggle;

  const _CameraGuidance({required this.showGuidance, required this.onToggle});

  @override
  State<_CameraGuidance> createState() => _CameraGuidanceState();
}

class _CameraGuidanceState extends State<_CameraGuidance> {
  @override
  Widget build(BuildContext context) {
    if (!widget.showGuidance) {
      // Just show the toggle when guidance is hidden
      return Positioned(
        top: 20,
        right: 20,
        child: _GuidanceToggle(showGuidance: false, onToggle: widget.onToggle),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // Top 25% Overlay - CEILING
            Expanded(
              flex: 25,
              child: _GuidanceSection(
                label: 'CEILING',
                description: 'Include 20-30% of ceiling',
                color: Colors.black.withValues(alpha: 0.3),
                showBottomDivider: true,
                alignment: Alignment.topCenter,
              ),
            ),
            // Middle 50% Overlay - PATH
            Expanded(
              flex: 50,
              child: _GuidanceSection(
                label: 'PATH',
                description: 'Keep path clear',
                color: Colors.transparent,
                showBottomDivider: true,
                alignment: Alignment.center,
              ),
            ),
            // Bottom 25% Overlay - FLOOR
            Expanded(
              flex: 25,
              child: _GuidanceSection(
                label: '', // Removed label to avoid overlap with button
                description: '', // Removed description
                color: Colors.black.withValues(alpha: 0.3),
                showBottomDivider: false,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
        // Toggle Button
        Positioned(
          top: 20,
          right: 20,
          child: _GuidanceToggle(showGuidance: true, onToggle: widget.onToggle),
        ),
      ],
    );
  }
}

class _GuidanceToggle extends StatelessWidget {
  final bool showGuidance;
  final VoidCallback onToggle;

  const _GuidanceToggle({required this.showGuidance, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showGuidance ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                showGuidance ? 'Hide Guide' : 'Show Guide',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidanceSection extends StatelessWidget {
  final String label;
  final String description;
  final Color color;
  final bool showBottomDivider;
  final Alignment alignment;

  const _GuidanceSection({
    required this.label,
    required this.description,
    required this.color,
    required this.alignment,
    this.showBottomDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: showBottomDivider
            ? Border(
                bottom: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  width: 2,
                ),
              )
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Align(
              alignment: alignment == Alignment.topCenter
                  ? Alignment.topCenter
                  : (alignment == Alignment.bottomCenter
                        ? Alignment.bottomCenter
                        : Alignment.center),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  if (label.isNotEmpty && description.isNotEmpty)
                    const SizedBox(height: 4),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showBottomDivider)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Icon(
                  Icons.expand_more,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
