/// Build-time settings. Override the API address with
/// `flutter run --dart-define=API_BASE=http://192.168.1.20:8080`.
///
/// The default works on a USB-connected phone after `adb reverse tcp:8080 tcp:8080`
/// (the phone's localhost:8080 is forwarded to the API on the PC).
class Config {
  static const String apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

  /// Must match the server's default search radius (app.geo.default-radius-m).
  static const int radiusMeters = 20;
}
