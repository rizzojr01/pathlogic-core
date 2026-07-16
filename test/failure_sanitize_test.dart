import 'package:flutter_test/flutter_test.dart';
import 'package:smart_sense/core/error/failures.dart';

void main() {
  test('technical Dart errors become friendly recovery messages', () {
    // The reported bug: `.first` on an empty list → "Bad state: No element".
    final msg = Failure.sanitize(StateError('No element').toString());
    expect(msg, contains('Please restart'));
    expect(msg.toLowerCase(), isNot(contains('no element')));

    // RangeError (index out of bounds) is also covered.
    expect(
      Failure.sanitize(RangeError.index(5, [1, 2]).toString()),
      contains('Please restart'),
    );
  });

  test('backend/business messages pass through verbatim', () {
    // Backend message is authoritative — shown as-is even when it happens to
    // contain digits or words that used to trigger the HTTP content buckets.
    for (final msg in const [
      'Password must be at least 8 characters.',
      'Amount exceeds 500 limit',
      'Forbidden action on this item',
      'This destination is not available on floor 3',
      'The server had a problem processing this request. Please try again shortly.',
    ]) {
      expect(Failure.sanitize(msg), msg);
    }
  });

  test('backend errors do NOT misfire the camera/GPS buckets', () {
    // Regression: "initialize" / bare "location" used to trigger the camera and
    // location-permission messages for unrelated backend failures.
    for (final backend in const [
      'Failed to initialize localization engine',
      'Localization failed for this location',
      'Could not initialize session',
    ]) {
      final out = Failure.sanitize(backend).toLowerCase();
      expect(out, isNot(contains('camera')), reason: backend);
      expect(out, isNot(contains('gps')), reason: backend);
    }

    // Genuine camera/GPS errors still map to their friendly messages.
    expect(Failure.sanitize('CameraException: permission'), contains('Camera'));
    expect(
      Failure.sanitize('Location services are disabled (GPS)'),
      contains('location services'),
    );
  });
}
