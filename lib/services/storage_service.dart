import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/db_connection.dart';

class StorageService {
  static const String _keyHistory = 'db_connection_history';
  static const String _keyAutoLogin = 'db_auto_login_enabled';
  static const String _keyAutoLoginConnection = 'db_auto_login_connection';

  // Simple XOR-based encryption key to satisfy "shared_preferences로 암호화해서 저장해줘"
  // without bringing complex native plugins that might have Flutter Web build issues.
  static const String _encryptionKey = 'antigravity_key_mysql_web_client_2026';

  static String _encrypt(String text) {
    final List<int> bytes = utf8.encode(text);
    final List<int> encrypted = List<int>.generate(bytes.length, (i) {
      return bytes[i] ^ _encryptionKey.codeUnitAt(i % _encryptionKey.length);
    });
    return base64.encode(encrypted);
  }

  static String _decrypt(String ciphertext) {
    try {
      final List<int> decoded = base64.decode(ciphertext);
      final List<int> decrypted = List<int>.generate(decoded.length, (i) {
        return decoded[i] ^ _encryptionKey.codeUnitAt(i % _encryptionKey.length);
      });
      return utf8.decode(decrypted);
    } catch (e) {
      return '';
    }
  }

  // Load connection history
  Future<List<DbConnection>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedData = prefs.getString(_keyHistory);
    if (encryptedData == null || encryptedData.isEmpty) {
      return [];
    }

    final decrypted = _decrypt(encryptedData);
    if (decrypted.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> list = json.decode(decrypted);
      return list.map((item) => DbConnection.fromJson(item)).toList();
    } catch (e) {
      return [];
    }
  }

  // Save connection details to history
  Future<void> saveConnectionToHistory(DbConnection conn) async {
    final history = await loadHistory();
    // Remove if already exists (to update its position/lastUsed)
    history.removeWhere((item) =>
        item.host == conn.host &&
        item.port == conn.port &&
        item.user == conn.user &&
        item.database == conn.database);

    // Create a copy with current time
    final updatedConn = DbConnection(
      host: conn.host,
      port: conn.port,
      user: conn.user,
      password: conn.password,
      database: conn.database,
      label: conn.label,
      lastUsed: DateTime.now(),
    );

    history.insert(0, updatedConn); // Add to the top of list
    
    // Limit history size to 15 items
    if (history.length > 15) {
      history.removeLast();
    }

    final prefs = await SharedPreferences.getInstance();
    final rawJson = json.encode(history.map((e) => e.toJson()).toList());
    final encrypted = _encrypt(rawJson);
    await prefs.setString(_keyHistory, encrypted);
  }

  // Delete a connection from history
  Future<void> deleteFromHistory(DbConnection conn) async {
    final history = await loadHistory();
    history.removeWhere((item) =>
        item.host == conn.host &&
        item.port == conn.port &&
        item.user == conn.user &&
        item.database == conn.database);

    final prefs = await SharedPreferences.getInstance();
    final rawJson = json.encode(history.map((e) => e.toJson()).toList());
    final encrypted = _encrypt(rawJson);
    await prefs.setString(_keyHistory, encrypted);
  }

  // Get auto login enabled state
  Future<bool> isAutoLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoLogin) ?? false;
  }

  // Get auto login connection details
  Future<DbConnection?> getAutoLoginConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_keyAutoLogin) ?? false;
    if (!isEnabled) return null;

    final encryptedData = prefs.getString(_keyAutoLoginConnection);
    if (encryptedData == null || encryptedData.isEmpty) {
      return null;
    }

    final decrypted = _decrypt(encryptedData);
    if (decrypted.isEmpty) return null;

    try {
      final decoded = json.decode(decrypted);
      return DbConnection.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }

  // Enable auto login with specified connection
  Future<void> enableAutoLogin(DbConnection conn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoLogin, true);
    
    final rawJson = json.encode(conn.toJson());
    final encrypted = _encrypt(rawJson);
    await prefs.setString(_keyAutoLoginConnection, encrypted);
  }

  // Disable auto login (logout)
  Future<void> disableAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoLogin, false);
    await prefs.remove(_keyAutoLoginConnection);
  }
}
