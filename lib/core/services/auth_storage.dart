// lib/core/services/auth_storage.dart

import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const String _keyToken = 'driver_token';
  static const String _keyDriverName = 'driver_name';
  static const String _keyDriverPhone = 'driver_phone';

  static Future<void> saveLoginData({
    required String token,
    required String fullName,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyDriverName, fullName);
    await prefs.setString(_keyDriverPhone, phone);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<String?> getDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDriverName);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
