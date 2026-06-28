import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/db_connection.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  DbConnection? _conn;
  DbConnection? get currentConnection => _conn;

  void setCurrentConnection(DbConnection conn) {
    _conn = conn;
  }

  void clearCurrentConnection() {
    _conn = null;
  }

  bool get isConnected => _conn != null;

  String get _apiBaseUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      // In flutter dev server, e.g. localhost:55432, connect to Go on localhost:10001.
      // Otherwise in production, relative to web server origin.
      if (uri.host == 'localhost' && uri.port != 80 && uri.port != 443 && uri.port != 10001) {
        return 'http://localhost:10001';
      }
      return '${uri.scheme}://${uri.host}:${uri.port}';
    }
    return 'http://localhost:10001';
  }

  Map<String, String> _getHeaders({String? overrideDb}) {
    if (_conn == null) {
      throw Exception("No active connection. Please connect first.");
    }
    return {
      'Content-Type': 'application/json',
      'X-DB-Host': _conn!.host,
      'X-DB-Port': _conn!.port.toString(),
      'X-DB-User': _conn!.user,
      'X-DB-Password': _conn!.password,
      'X-DB-Database': overrideDb ?? _conn!.database ?? '',
    };
  }

  // Connects (verifies credentials) and returns database list if successful
  Future<List<String>> connect(DbConnection conn) async {
    final url = Uri.parse('$_apiBaseUrl/api/connect');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-DB-Host': conn.host,
        'X-DB-Port': conn.port.toString(),
        'X-DB-User': conn.user,
        'X-DB-Password': conn.password,
        'X-DB-Database': conn.database ?? '',
      },
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      _conn = conn;
      return List<String>.from(data['databases'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to connect to MySQL database.');
    }
  }

  // Fetch databases list
  Future<List<String>> getDatabases() async {
    final url = Uri.parse('$_apiBaseUrl/api/databases');
    final response = await http.get(url, headers: _getHeaders());

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<String>.from(data['databases'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve databases.');
    }
  }

  // Fetch tables list in database
  Future<List<String>> getTables(String db) async {
    final url = Uri.parse('$_apiBaseUrl/api/tables?database=${Uri.encodeComponent(db)}');
    final response = await http.get(url, headers: _getHeaders(overrideDb: db));

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<String>.from(data['tables'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve tables.');
    }
  }

  // Fetch columns schemas in a table
  Future<List<Map<String, dynamic>>> getColumns(String db, String table) async {
    final url = Uri.parse(
      '$_apiBaseUrl/api/columns?database=${Uri.encodeComponent(db)}&table=${Uri.encodeComponent(table)}'
    );
    final response = await http.get(url, headers: _getHeaders(overrideDb: db));

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<Map<String, dynamic>>.from(data['columns'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve columns.');
    }
  }

  // Executes arbitrary queries separated by semicolon
  Future<Map<String, dynamic>> runQueries(String sql, {String? overrideDb}) async {
    final url = Uri.parse('$_apiBaseUrl/api/query');
    final response = await http.post(
      url,
      headers: _getHeaders(overrideDb: overrideDb),
      body: json.encode({
        'query': sql,
        'database': overrideDb,
      }),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      // Sometimes it returns 400 or 500, but we still want the details in response
      if (data is Map && data.containsKey('message')) {
        return {
          'success': false,
          'message': data['message'],
          'results': data['results'] ?? [],
          'logs': data['logs'] ?? [],
        };
      }
      throw Exception(data['message'] ?? 'Failed to execute query.');
    }
  }

  // Execute structural DDL changes (Create table, alter column, drop column, index)
  Future<Map<String, dynamic>> executeChanges(
    String db,
    String? table,
    List<Map<String, dynamic>> changes,
  ) async {
    final url = Uri.parse('$_apiBaseUrl/api/execute-changes');
    final response = await http.post(
      url,
      headers: _getHeaders(overrideDb: db),
      body: json.encode({
        'database': db,
        'table': table,
        'changes': changes,
      }),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to execute structural changes.');
    }
  }

  // Search databases, tables, and column names globally
  Future<Map<String, dynamic>> searchSchema(String query, {String? db}) async {
    final uri = Uri.parse('$_apiBaseUrl/api/search-schema').replace(
      queryParameters: {
        'query': query,
        if (db != null) 'database': db,
      },
    );
    final response = await http.get(
      uri,
      headers: _getHeaders(overrideDb: db),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to search schema.');
    }
  }

  // Fetch query execution history from mysql.query_history
  Future<Map<String, dynamic>> getQueryHistory({
    String? startDate,
    String? endDate,
    String? keyword,
    String? db,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/api/query-history').replace(
      queryParameters: {
        if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
        if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (db != null) 'database': db,
      },
    );
    final response = await http.get(
      uri,
      headers: _getHeaders(overrideDb: db),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to load query history.');
    }
  }

  // Fetch all MySQL users
  Future<List<dynamic>> getUsers() async {
    final url = Uri.parse('$_apiBaseUrl/api/users');
    final response = await http.get(url, headers: _getHeaders());
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data['users'] ?? [];
    } else {
      throw Exception(data['message'] ?? '사용자 목록을 불러오는데 실패했습니다.');
    }
  }

  // Fetch database permissions detail for a MySQL user
  Future<Map<String, dynamic>> getUserDetail(String user, String host) async {
    final uri = Uri.parse('$_apiBaseUrl/api/users/detail').replace(
      queryParameters: {
        'user': user,
        'host': host,
      },
    );
    final response = await http.get(uri, headers: _getHeaders());
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? '사용자 권한 상세 정보를 불러오는데 실패했습니다.');
    }
  }

  // Create new MySQL user
  Future<void> createUser(String username, String password, String host, bool superuser, List<Map<String, dynamic>> grants) async {
    final url = Uri.parse('$_apiBaseUrl/api/users/create');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'username': username,
        'password': password,
        'host': host,
        'superuser': superuser,
        'grants': grants,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? '사용자 생성에 실패했습니다.');
    }
  }

  // Delete a MySQL user
  Future<void> deleteUser(String username, String host) async {
    final url = Uri.parse('$_apiBaseUrl/api/users/delete');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'username': username,
        'host': host,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? '사용자 삭제에 실패했습니다.');
    }
  }

  // Update a MySQL user
  Future<void> updateUser(String username, String host, String newHost, String password, bool superuser, List<Map<String, dynamic>> grants) async {
    final url = Uri.parse('$_apiBaseUrl/api/users/update');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'username': username,
        'host': host,
        'new_host': newHost,
        'password': password,
        'superuser': superuser,
        'grants': grants,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? '사용자 정보 수정에 실패했습니다.');
    }
  }

  // Update a single row in an editable grid
  Future<Map<String, dynamic>> updateRow(
    String db,
    String table,
    Map<String, dynamic> pkValues,
    Map<String, dynamic> updatedValues,
  ) async {
    final url = Uri.parse('$_apiBaseUrl/api/update-row');
    final response = await http.post(
      url,
      headers: _getHeaders(overrideDb: db),
      body: json.encode({
        'database': db,
        'table': table,
        'pk_values': pkValues,
        'updated_values': updatedValues,
      }),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to update row.');
    }
  }

  // Insert a single row in an editable grid
  Future<Map<String, dynamic>> insertRow(
    String db,
    String table,
    Map<String, dynamic> values,
  ) async {
    final url = Uri.parse('$_apiBaseUrl/api/insert-row');
    final response = await http.post(
      url,
      headers: _getHeaders(overrideDb: db),
      body: json.encode({
        'database': db,
        'table': table,
        'values': values,
      }),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to insert row.');
    }
  }

  // Execute batch queries on multiple databases
  Future<Map<String, dynamic>> runBatchQueries(List<String> dbs, String sql) async {
    final url = Uri.parse('$_apiBaseUrl/api/batch-query');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'databases': dbs,
        'query': sql,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to execute batch queries.');
    }
  }

  // Get auto backup configurations
  Future<List<Map<String, dynamic>>> getAutoBackupConfigs() async {
    final url = Uri.parse('$_apiBaseUrl/api/auto-backup/configs');
    final response = await http.get(url, headers: _getHeaders());
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<Map<String, dynamic>>.from(data['configs'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve auto backup configurations.');
    }
  }

  // Save auto backup configuration
  Future<void> saveAutoBackupConfig(String dbName, String backupTime, int keepDays, bool isActive) async {
    final url = Uri.parse('$_apiBaseUrl/api/auto-backup/save');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'db_name': dbName,
        'backup_time': backupTime,
        'keep_days': keepDays,
        'is_active': isActive,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to save auto backup configuration.');
    }
  }

  // Backup selected databases immediately
  Future<void> backupNow(List<String> dbs, String dirName) async {
    final url = Uri.parse('$_apiBaseUrl/api/backup-now');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'databases': dbs,
        'directory_name': dirName,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to perform immediate backup.');
    }
  }

  // Fetch backup directories
  Future<List<String>> getBackupDirectories() async {
    final url = Uri.parse('$_apiBaseUrl/api/backup/directories');
    final response = await http.get(url, headers: _getHeaders());
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<String>.from(data['directories'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve backup directories.');
    }
  }

  // Fetch backup files inside a directory
  Future<List<Map<String, dynamic>>> getBackupFiles(String dirName) async {
    final url = Uri.parse('$_apiBaseUrl/api/backup/files?directory=${Uri.encodeComponent(dirName)}');
    final response = await http.get(url, headers: _getHeaders());
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<Map<String, dynamic>>.from(data['files'] ?? []);
    } else {
      throw Exception(data['message'] ?? 'Failed to retrieve backup files.');
    }
  }

  // Restore database backups
  Future<void> restoreBackup(
    String dirName,
    List<String> files,
    Map<String, String> targetDatabases,
    bool cleanRestore,
  ) async {
    final url = Uri.parse('$_apiBaseUrl/api/backup/restore');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'directory': dirName,
        'files': files,
        'target_databases': targetDatabases,
        'clean_restore': cleanRestore,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to restore backup files.');
    }
  }

  // Copy/clone databases into a target database
  Future<void> copyDatabase(List<String> srcDbs, String targetDb) async {
    final url = Uri.parse('$_apiBaseUrl/api/db-copy');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: json.encode({
        'source_databases': srcDbs,
        'target_database': targetDb,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to copy databases.');
    }
  }
}
