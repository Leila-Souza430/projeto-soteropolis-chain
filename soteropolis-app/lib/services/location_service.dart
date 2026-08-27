import 'package:geolocator/geolocator.dart';

/// Location services are off at the OS level (airplane mode, user disabled
/// GPS entirely) - distinct from a permission denial so the UI can point at
/// the right settings screen. Named distinctly from geolocator's own
/// LocationServiceDisabledException (re-exported via package:geolocator/
/// geolocator.dart) to avoid an ambiguous_import.
class LocationServiceOffException implements Exception {}

/// The citizen denied the location permission (once, or permanently).
class LocationPermissionDeniedException implements Exception {}

/// Thin wrapper around geolocator: centralizes the
/// service-enabled -> permission-check -> permission-request sequence so
/// every call site doesn't have to repeat it.
class LocationService {
  /// Throws [LocationServiceDisabledException] or
  /// [LocationPermissionDeniedException] if a position can't be read.
  /// camera_descarte_screen.dart calls this once, up front, to decide
  /// whether to show the permission-denied fallback screen before letting
  /// the citizen attempt a capture at all.
  Future<void> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationServiceOffException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedException();
    }
  }

  /// Reads the current GPS fix. Callers must invoke this AT THE CAMERA
  /// SHUTTER INSTANT, not when the screen opens or the ecoponto is picked -
  /// the antifraude geofencing check (SPEC 3.2) is only meaningful if the
  /// coordinates reflect where the citizen is standing at the moment they
  /// take the photo.
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
