import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_sense/shared/services/floor_plan_cache_service.dart';

// Guards the map-refresh plumbing: stored HTTP validators must be readable and,
// critically, cleared on invalidation — a lingering ETag would make a changed
// map return 304 forever (the 24h-delay bug in a new disguise).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('validators are read back and wiped when the building cache clears', () async {
    // Key format mirrors FloorPlanCacheService (fp_etag_/fp_lastmod_ prefixes).
    SharedPreferences.setMockInitialValues({
      'fp_etag_NYC_Tower_1': '"abc123"',
      'fp_lastmod_NYC_Tower_1': 'Wed, 01 Jan 2026 00:00:00 GMT',
    });
    final cache = FloorPlanCacheService(await SharedPreferences.getInstance());

    final v = cache.getCacheValidators(
      place: 'NYC',
      building: 'Tower',
      floor: '1',
    );
    expect(v.etag, '"abc123"');
    expect(v.lastModified, isNotNull);

    await cache.clearCacheForBuilding(place: 'NYC', building: 'Tower');

    final after = cache.getCacheValidators(
      place: 'NYC',
      building: 'Tower',
      floor: '1',
    );
    expect(after.etag, isNull);
    expect(after.lastModified, isNull);
  });
}
