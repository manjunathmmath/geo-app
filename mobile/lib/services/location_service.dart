import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => message;
}

class LocationService {
  /// A fresh, high-accuracy fix. Asks for permission the first time.
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Location is switched off. Turn on GPS in your phone settings.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('GeoApp needs your location to find posts around you. Please allow it.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('Location permission is blocked. Enable it for GeoApp in the phone settings.');
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)),
      );
    } catch (_) {
      throw const LocationException('Could not get a GPS fix. Move to an open area and try again.');
    }
  }

  /// Position updates, one for roughly every 5 m moved.
  static Stream<Position> updates() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
      );

  static double metresBetween(Position a, Position b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
}
