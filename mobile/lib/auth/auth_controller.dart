import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// Who is signed in. Browsing nearby posts works without signing in.
class AuthController extends ChangeNotifier {
  AuthController(this._api);

  final ApiClient _api;
  Me? user;
  bool restoring = true;

  bool get signedIn => user != null;

  /// Restores the previous session when the app starts.
  Future<void> restore() async {
    if (_api.hasTokens) {
      try {
        user = await _api.me();
      } on ApiException catch (e) {
        // A real rejection means the session is gone; a network error keeps the tokens for next time.
        if (e.status == 401 || e.status == 403) await _api.logout();
      }
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    user = await _api.login(email, password);
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    user = await _api.register(email, password);
    notifyListeners();
  }

  Future<void> logout() async {
    user = null;
    notifyListeners();
    await _api.logout();
  }
}
