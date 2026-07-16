import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../core/constants/api_routes.dart';
import '../../core/utils/logger.dart';
import '../../injection.dart';
import 'floor_plan_cache_service.dart';

/// Current status of the map synchronization process.
class MapSyncStatus {
  final bool isSyncing;
  final String? errorMessage;
  final int downloadedCount;
  final int totalCount;
  final DateTime? lastSyncTime;

  const MapSyncStatus({
    this.isSyncing = false,
    this.errorMessage,
    this.downloadedCount = 0,
    this.totalCount = 0,
    this.lastSyncTime,
  });

  MapSyncStatus copyWith({
    bool? isSyncing,
    String? errorMessage,
    int? downloadedCount,
    int? totalCount,
    DateTime? lastSyncTime,
  }) {
    return MapSyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: errorMessage,
      downloadedCount: downloadedCount ?? this.downloadedCount,
      totalCount: totalCount ?? this.totalCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// Result of a map catalog download attempt.
class MapDownloadResult {
  final bool success;
  final List<String> downloadedFloors;
  final String? errorMessage;

  const MapDownloadResult({
    required this.success,
    required this.downloadedFloors,
    this.errorMessage,
  });
}

/// Service that syncs all floor-plan images for a building using the
/// `/map_download/catalog` API.
class MapDownloadService {
  final FloorPlanCacheService _cache;
  final AppLogger _logger = getIt<AppLogger>();

  /// Observable sync status for UI listeners.
  final ValueNotifier<MapSyncStatus> syncStatus = ValueNotifier(
    const MapSyncStatus(),
  );

  // Separate Dio instance for raw image downloads
  late final Dio _dio;

  MapDownloadService(this._cache) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 3),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    // Bypass SSL for dev server
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );
  }

  /// Downloads all floor maps for the given [place]/[building] combination.
  /// If [force] is true, it clears the old cache first. Otherwise it revalidates
  /// each cached floor against the server with HTTP validators (ETag /
  /// Last-Modified): unchanged floors return 304 and are kept, changed floors
  /// return 200 and are refreshed immediately — so newly published maps arrive
  /// on the next sync instead of after a 24h window. Floors whose server sends
  /// no validator fall back to the 24h freshness check.
  Future<MapDownloadResult> syncMapsForBuilding({
    required String place,
    required String building,
    required String baseUrl,
    bool force = false,
  }) async {
    _logger.info(
      'MapDownloadService: Starting sync for $place / $building (force: $force)',
    );
    syncStatus.value = syncStatus.value.copyWith(
      isSyncing: true,
      errorMessage: null,
      downloadedCount: 0,
      totalCount: 0,
    );

    try {
      // ── 1. Fetch catalog ──────────────────────────────────────────────────
      final catalogDio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      catalogDio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
          return client;
        },
      );

      final catalogResp = await catalogDio.post<Map<String, dynamic>>(
        ApiRoutes.mapDownloadCatalog,
        data: {'building': building, 'place': place},
      );

      final floors = (catalogResp.data?['floors'] as List<dynamic>?) ?? [];
      if (floors.isEmpty) {
        _logger.warning('MapDownloadService: No floors found in catalog');
        return const MapDownloadResult(
          success: false,
          downloadedFloors: [],
          errorMessage: 'Catalog returned no floors.',
        );
      }

      _logger.info(
        'MapDownloadService: Found ${floors.length} floors in catalog',
      );
      syncStatus.value = syncStatus.value.copyWith(totalCount: floors.length);

      // ── 2. Handle cache clearing ──────────────────────────────────────────
      if (force) {
        _logger.info('MapDownloadService: Force sync enabled. Clearing cache.');
        await _cache.clearCacheForBuilding(place: place, building: building);
      }

      // ── 3. Download each floor image with concurrency control ────────────
      final downloadedFloors = <String>[];
      final skippedFloors = <String>[];
      final errors = <String>[];

      // Concurrency limit: 3
      const int maxConcurrency = 3;
      final List<dynamic> remainingFloors = List.from(floors);

      Future<void> downloadWorker() async {
        while (remainingFloors.isNotEmpty) {
          final floorEntry = remainingFloors.removeAt(0);
          final floorKey = floorEntry['floor'] as String? ?? '';
          final downloadUrl = floorEntry['download_url'] as String? ?? '';

          if (floorKey.isEmpty || downloadUrl.isEmpty) continue;

          final isCached = _cache.hasCachedFloorPlan(
            place: place,
            building: building,
            floor: floorKey,
          );

          // Revalidate cached floors against the server using HTTP validators
          // (ETag / Last-Modified) so a republished map is picked up on the very
          // next sync — no 24h wait, no reinstall. A 304 means "unchanged, keep
          // cache"; a 200 delivers the new image.
          final validators = isCached
              ? _cache.getCacheValidators(
                  place: place,
                  building: building,
                  floor: floorKey,
                )
              : (etag: null, lastModified: null);
          final hasValidator =
              validators.etag != null || validators.lastModified != null;

          // Only when the server offers no validator do we fall back to the
          // time-based skip — otherwise we'd re-download every floor on every
          // launch. With a validator, conditional GETs stay cheap (304s).
          if (!force && isCached && !hasValidator) {
            final stale = _cache.isCacheStale(
              place: place,
              building: building,
              floor: floorKey,
            );
            if (!stale) {
              _logger.info(
                'MapDownloadService: Skipping $floorKey (fresh, no validator)',
              );
              skippedFloors.add(floorKey);
              syncStatus.value = syncStatus.value.copyWith(
                downloadedCount: downloadedFloors.length + skippedFloors.length,
              );
              continue;
            }
          }

          final conditionalHeaders = <String, String>{
            if (!force && isCached && validators.etag != null)
              'If-None-Match': validators.etag!,
            if (!force && isCached && validators.lastModified != null)
              'If-Modified-Since': validators.lastModified!,
          };

          bool success = false;
          int attempts = 0;
          const int maxAttempts = 3;

          while (!success && attempts < maxAttempts) {
            attempts++;
            try {
              _logger.info(
                'MapDownloadService: Downloading $floorKey (Attempt $attempts)',
              );
              final response = await _dio.get<List<int>>(
                downloadUrl,
                options: Options(
                  responseType: ResponseType.bytes,
                  headers: conditionalHeaders,
                  // Accept 304 so an unchanged map doesn't throw.
                  validateStatus: (s) => s != null && (s == 200 || s == 304),
                ),
              );

              if (response.statusCode == 304) {
                // Unchanged — keep the cached image, just refresh its timestamp.
                await _cache.touchCache(
                  place: place,
                  building: building,
                  floor: floorKey,
                );
                skippedFloors.add(floorKey);
                syncStatus.value = syncStatus.value.copyWith(
                  downloadedCount:
                      downloadedFloors.length + skippedFloors.length,
                );
                success = true;
                _logger.info('MapDownloadService: $floorKey unchanged (304)');
                break;
              }

              final bytes = response.data;
              if (bytes != null && bytes.isNotEmpty) {
                await _cache.cacheFloorPlanBytes(
                  place: place,
                  building: building,
                  floor: floorKey,
                  bytes: Uint8List.fromList(bytes),
                  etag: response.headers.value('etag'),
                  lastModified: response.headers.value('last-modified'),
                );
                downloadedFloors.add(floorKey);
                syncStatus.value = syncStatus.value.copyWith(
                  downloadedCount:
                      downloadedFloors.length + skippedFloors.length,
                );
                success = true;
                _logger.info(
                  'MapDownloadService: Successfully synced $floorKey',
                );
              } else {
                if (attempts == maxAttempts) {
                  errors.add('$floorKey: empty response');
                }
              }
            } catch (e) {
              _logger.error(
                'MapDownloadService: Error downloading $floorKey: $e',
              );
              if (attempts == maxAttempts) errors.add('$floorKey: $e');
              // Short delay before retry
              if (!success && attempts < maxAttempts) {
                await Future.delayed(const Duration(seconds: 1));
              }
            }
          }
        }
      }

      // Start workers
      await Future.wait(
        List.generate(
          floors.length < maxConcurrency ? floors.length : maxConcurrency,
          (_) => downloadWorker(),
        ),
      );

      final totalProcessed = downloadedFloors.length + skippedFloors.length;
      final result = MapDownloadResult(
        success: totalProcessed > 0,
        downloadedFloors: downloadedFloors,
        errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
      );

      syncStatus.value = syncStatus.value.copyWith(
        isSyncing: false,
        errorMessage: result.errorMessage,
        lastSyncTime: DateTime.now(),
      );

      _logger.info(
        'MapDownloadService: Sync complete. Total: $totalProcessed, '
        'Downloaded: ${downloadedFloors.length}, Skipped: ${skippedFloors.length}',
      );
      return result;
    } catch (e) {
      _logger.error('MapDownloadService: Critical sync failure: $e');
      final result = MapDownloadResult(
        success: false,
        downloadedFloors: [],
        errorMessage: 'Catalog fetch failed: $e',
      );

      syncStatus.value = syncStatus.value.copyWith(
        isSyncing: false,
        errorMessage: result.errorMessage,
      );

      return result;
    }
  }
}
