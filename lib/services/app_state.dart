import 'package:flutter/material.dart';
import '../models/db_connection.dart';
import 'api_service.dart';
import 'storage_service.dart';

class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  DbConnection? get currentConnection => _api.currentConnection;
  bool get isConnected => _api.isConnected;

  List<String> _databases = [];
  List<String> get databases => _databases;

  Set<String> _expandedDatabases = {};
  Set<String> get expandedDatabases => _expandedDatabases;

  Map<String, List<String>> _tables = {};
  Map<String, List<String>> get tables => _tables;

  String? _selectedDatabase;
  String? get selectedDatabase => _selectedDatabase;

  String? _selectedTable;
  String? get selectedTable => _selectedTable;

  List<Map<String, dynamic>> _tableColumns = [];
  List<Map<String, dynamic>> get tableColumns => _tableColumns;

  // Staged changes for the current table structure
  // Formats:
  // - {'action': 'add_column', 'column': Map}
  // - {'action': 'modify_column', 'old_name': String, 'column': Map}
  // - {'action': 'drop_column', 'field_name': String}
  // - {'action': 'create_table', 'table_name': String, 'columns': List}
  // - {'action': 'drop_table', 'table_name': String}
  // - {'action': 'create_index', 'table_name': String, 'index_name': String, 'columns': List, 'unique': Bool}
  List<Map<String, dynamic>> _stagedChanges = [];
  List<Map<String, dynamic>> get stagedChanges => _stagedChanges;

  // Menu: 'Table layout' or 'SQL Editor'
  String _activeMenu = 'Table layout';
  String get activeMenu => _activeMenu;

  // SQL Editor state
  String _sqlEditorText = '';
  String get sqlEditorText => _sqlEditorText;
  
  // Results of the SQL queries: list of maps
  List<Map<String, dynamic>> _sqlResults = [];
  List<Map<String, dynamic>> get sqlResults => _sqlResults;

  List<Map<String, dynamic>> _sqlLogs = [];
  List<Map<String, dynamic>> get sqlLogs => _sqlLogs;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Active editable grid state (when running 'edit table' or from main screen)
  bool _isEditingTableDirectly = false;
  bool get isEditingTableDirectly => _isEditingTableDirectly;
  String? _editTableName;
  String? get editTableName => _editTableName;
  List<String> _editTablePKs = [];
  List<String> get editTablePKs => _editTablePKs;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> get searchResults => _searchResults;

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    try {
      final res = await _api.searchSchema(query, db: _selectedDatabase);
      if (res['results'] != null) {
        _searchResults = List<Map<String, dynamic>>.from(res['results']);
      }
    } catch (e) {
      print("Schema search error: $e");
    }
    notifyListeners();
  }

  bool _showQueryHistory = false;
  bool get showQueryHistory => _showQueryHistory;

  List<Map<String, dynamic>> _queryHistoryList = [];
  List<Map<String, dynamic>> get queryHistoryList => _queryHistoryList;

  void toggleShowQueryHistory() {
    _showQueryHistory = !_showQueryHistory;
    notifyListeners();
  }

  Future<void> fetchQueryHistory({
    String? startDate,
    String? endDate,
    String? keyword,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _api.getQueryHistory(
        startDate: startDate,
        endDate: endDate,
        keyword: keyword,
        db: _selectedDatabase,
      );
      if (res['history'] != null) {
        _queryHistoryList = List<Map<String, dynamic>>.from(res['history']);
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<dynamic>> getUsers() async {
    _isLoading = true;
    notifyListeners();
    try {
      final list = await _api.getUsers();
      return list;
    } catch (e) {
      _errorMessage = e.toString();
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> getUserDetail(String user, String host) async {
    _isLoading = true;
    notifyListeners();
    try {
      final detail = await _api.getUserDetail(user, host);
      return detail;
    } catch (e) {
      _errorMessage = e.toString();
      return {};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser(String username, String password, String host, bool superuser, List<Map<String, dynamic>> grants) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.createUser(username, password, host, superuser, grants);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteUser(String username, String host) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.deleteUser(username, host);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUser(String username, String host, String newHost, String password, bool superuser, List<Map<String, dynamic>> grants) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.updateUser(username, host, newHost, password, superuser, grants);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void changeMenu(String menu) {
    if (_activeMenu != menu) {
      // Discard staged changes if switching table menu
      _stagedChanges.clear();
      _activeMenu = menu;
      notifyListeners();
    }
  }

  void setSqlText(String text) {
    _sqlEditorText = text;
  }

  Future<void> connect(DbConnection conn, bool remember, bool autoLogin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final dbList = await _api.connect(conn);
      _databases = dbList;

      if (remember) {
        await _storage.saveConnectionToHistory(conn);
      }
      if (autoLogin) {
        await _storage.enableAutoLogin(conn);
      } else {
        await _storage.disableAutoLogin();
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _api.clearCurrentConnection();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> autoConnect(DbConnection conn) async {
    _isLoading = true;
    notifyListeners();
    try {
      final dbList = await _api.connect(conn);
      _databases = dbList;
    } catch (e) {
      _errorMessage = "자동 로그인 실패: ${e.toString()}";
      _api.clearCurrentConnection();
      await _storage.disableAutoLogin();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _api.clearCurrentConnection();
    _databases.clear();
    _tables.clear();
    _selectedDatabase = null;
    _selectedTable = null;
    _tableColumns.clear();
    _stagedChanges.clear();
    _sqlResults.clear();
    _sqlLogs.clear();
    _isEditingTableDirectly = false;
    _editTableName = null;
    _editTablePKs.clear();
    await _storage.disableAutoLogin();
    notifyListeners();
  }

  Future<void> refreshDatabases() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final dbList = await _api.getDatabases();
      _databases = dbList;

      // Refresh table list for all expanded databases
      for (var db in _expandedDatabases) {
        try {
          final tblList = await _api.getTables(db);
          _tables[db] = tblList;
        } catch (_) {}
      }

      // Refresh columns for the currently selected table
      if (_selectedDatabase != null && _selectedTable != null) {
        try {
          final cols = await _api.getColumns(_selectedDatabase!, _selectedTable!);
          _tableColumns = cols;
        } catch (_) {}
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> dropDatabase(String dbName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final sql = "DROP DATABASE `$dbName`;";
      await _api.runQueries(sql);
      
      // If the dropped DB was active, clear selection
      if (_selectedDatabase == dbName) {
        _selectedDatabase = null;
        _selectedTable = null;
        _tables.remove(dbName);
      }
      
      await refreshDatabases();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> dropTable(String dbName, String tableName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final sql = "DROP TABLE `$dbName`.`$tableName`;";
      await _api.runQueries(sql, overrideDb: dbName);
      
      // If the dropped Table was active, clear selection
      if (_selectedDatabase == dbName && _selectedTable == tableName) {
        _selectedTable = null;
        _tableColumns.clear();
      }
      
      if (_tables.containsKey(dbName)) {
        _tables[dbName]?.remove(tableName);
      }
      
      await refreshDatabases();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleDatabaseExpanded(String db) async {
    if (_expandedDatabases.contains(db)) {
      _expandedDatabases.remove(db);
    } else {
      _expandedDatabases.add(db);
      if (!_tables.containsKey(db)) {
        await refreshTables(db);
      }
    }
    notifyListeners();
  }

  Future<void> refreshTables(String db) async {
    try {
      final tblList = await _api.getTables(db);
      _tables[db] = tblList;
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  void selectDatabase(String db) {
    if (_selectedDatabase != db) {
      // Discard staged changes
      _stagedChanges.clear();
      _selectedDatabase = db;
      _selectedTable = null;
      _tableColumns.clear();
      notifyListeners();
    }
  }

  Future<void> selectTable(String db, String table) async {
    // Discard staged changes
    _stagedChanges.clear();
    _selectedDatabase = db;
    _selectedTable = table;
    _tableColumns.clear();
    _isLoading = true;
    notifyListeners();

    try {
      final cols = await _api.getColumns(db, table);
      _tableColumns = cols;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Staging Structure Changes ---
  void addColumn(Map<String, dynamic> col) {
    _stagedChanges.add({
      'action': 'add_column',
      'column': col,
    });
    notifyListeners();
  }

  void modifyColumn(String oldName, Map<String, dynamic> col) {
    // If there is already a staged add_column for oldName, modify it directly
    final addIdx = _stagedChanges.indexWhere(
        (c) => c['action'] == 'add_column' && c['column']['field_name'] == oldName);
    if (addIdx != -1) {
      _stagedChanges[addIdx]['column'] = col;
      notifyListeners();
      return;
    }

    // If there is already a modify_column for oldName, update it
    final modIdx = _stagedChanges.indexWhere(
        (c) => c['action'] == 'modify_column' && c['old_name'] == oldName);
    if (modIdx != -1) {
      _stagedChanges[modIdx]['column'] = col;
      notifyListeners();
      return;
    }

    _stagedChanges.add({
      'action': 'modify_column',
      'old_name': oldName,
      'column': col,
    });
    notifyListeners();
  }

  void deleteColumn(String fieldName) {
    // If it was just added in staged changes, remove it from staged changes
    final addIdx = _stagedChanges.indexWhere(
        (c) => c['action'] == 'add_column' && c['column']['field_name'] == fieldName);
    if (addIdx != -1) {
      _stagedChanges.removeAt(addIdx);
      notifyListeners();
      return;
    }

    // If it was modified in staged changes, remove that modification
    _stagedChanges.removeWhere(
        (c) => c['action'] == 'modify_column' && c['old_name'] == fieldName);

    _stagedChanges.add({
      'action': 'drop_column',
      'field_name': fieldName,
    });
    notifyListeners();
  }

  void stageTableCreation(String tableName, List<Map<String, dynamic>> columns) {
    _stagedChanges.add({
      'action': 'create_table',
      'table_name': tableName,
      'columns': columns,
    });
    notifyListeners();
  }

  void stageTableDrop(String tableName) {
    _stagedChanges.add({
      'action': 'drop_table',
      'table_name': tableName,
    });
    notifyListeners();
  }

  void stageIndexCreation(String tableName, String indexName, List<String> columns, bool unique) {
    _stagedChanges.add({
      'action': 'create_index',
      'table_name': tableName,
      'index_name': indexName,
      'columns': columns,
      'unique': unique,
    });
    notifyListeners();
  }

  void clearStagedChanges() {
    _stagedChanges.clear();
    notifyListeners();
  }

  Future<void> saveTableChanges() async {
    if (_stagedChanges.isEmpty) return;
    if (_selectedDatabase == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final res = await _api.executeChanges(_selectedDatabase!, _selectedTable, _stagedChanges);
      
      // Update logs in SQL Editor
      if (res['logs'] != null) {
        _sqlLogs.addAll(List<Map<String, dynamic>>.from(res['logs']));
      }

      _stagedChanges.clear();

      // Refresh table list and active table columns if they exist
      await refreshTables(_selectedDatabase!);
      if (_selectedTable != null) {
        // If table was dropped, clear table selection
        final wasDropped = _stagedChanges.any((c) => c['action'] == 'drop_table' && c['table_name'] == _selectedTable);
        if (wasDropped) {
          _selectedTable = null;
          _tableColumns.clear();
        } else {
          await selectTable(_selectedDatabase!, _selectedTable!);
        }
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- visibleColumns for staged UI schema view ---
  List<Map<String, dynamic>> get visibleColumns {
    List<Map<String, dynamic>> cols = _tableColumns.map((c) => Map<String, dynamic>.from(c)).toList();
    
    for (var change in _stagedChanges) {
      final action = change['action'];
      if (action == 'add_column') {
        cols.add(Map<String, dynamic>.from(change['column']));
      } else if (action == 'modify_column') {
        final oldName = change['old_name'];
        final updatedCol = change['column'];
        final idx = cols.indexWhere((c) => c['field_name'] == oldName);
        if (idx != -1) {
          cols[idx] = Map<String, dynamic>.from(updatedCol);
        }
      } else if (action == 'drop_column') {
        final fieldName = change['field_name'];
        cols.removeWhere((c) => c['field_name'] == fieldName);
      }
    }
    return cols;
  }

  // --- SQL Editor Execution ---
  Future<void> runQueries(String sql) async {
    if (sql.trim().isEmpty) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Check if the query is an "edit" command
    // Format: edit table_name [where condition] [limit count]; or edit table_name;
    final cleanSql = sql.trim();
    int? limit;
    String queryWithoutLimit = cleanSql;
    final limitMatch = RegExp(r'\s+limit\s+(\d+);?$', caseSensitive: false).firstMatch(cleanSql);
    if (limitMatch != null) {
      limit = int.tryParse(limitMatch.group(1)!);
      queryWithoutLimit = cleanSql.substring(0, limitMatch.start).trim() + (cleanSql.endsWith(';') ? ';' : '');
    }

    final editRegExp = RegExp(r'^edit\s+([a-zA-Z0-9_`]+)(?:\s+where\s+(.+))?;?$', caseSensitive: false);
    final match = editRegExp.firstMatch(queryWithoutLimit);

    if (match != null) {
      final rawTableName = match.group(1)!;
      final cleanTableName = rawTableName.replaceAll('`', '');
      final whereCondition = match.group(2);
      
      await setupDirectTableEditing(cleanTableName, whereCondition: whereCondition, limit: limit);
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isEditingTableDirectly = false;
    _editTableName = null;
    _editTablePKs.clear();

    try {
      final res = await _api.runQueries(sql, overrideDb: _selectedDatabase);
      
      // Update results
      _sqlResults = List<Map<String, dynamic>>.from(res['results'] ?? []);
      
      // Add logs
      if (res['logs'] != null) {
        _sqlLogs.addAll(List<Map<String, dynamic>>.from(res['logs']));
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Setup editable grid for direct table editing
  Future<void> setupDirectTableEditing(String tableName, {String? database, String? whereCondition, int? limit}) async {
    final targetDb = database ?? _selectedDatabase;
    if (targetDb == null) {
      _errorMessage = "먼저 데이터베이스를 선택해주세요.";
      return;
    }

    _isLoading = true;
    _selectedDatabase = targetDb; // Switch database context automatically
    notifyListeners();

    try {
      // 1. Fetch table columns to identify primary keys
      final cols = await _api.getColumns(targetDb, tableName);
      final pks = cols.where((c) => c['is_pk'] == true).map((c) => c['field_name'].toString()).toList();
      
      _editTableName = tableName;
      _editTablePKs = pks;
      _isEditingTableDirectly = true;
      _activeMenu = 'SQL Editor'; // Switch menu to Editor

      // 2. Generate and run SELECT query
      String selectSql = "SELECT * FROM `$tableName`";
      if (whereCondition != null && whereCondition.trim().isNotEmpty) {
        selectSql += " WHERE $whereCondition";
      }
      if (limit != null) {
        selectSql += " LIMIT $limit";
      }
      selectSql += ";";

      // Keep actual command text in editor
      _sqlEditorText = "edit `$tableName`" + 
          (whereCondition != null ? " where $whereCondition" : "") + 
          (limit != null ? " limit $limit" : "") + ";";

      final res = await _api.runQueries(selectSql, overrideDb: targetDb);
      _sqlResults = List<Map<String, dynamic>>.from(res['results'] ?? []);
      
      if (res['logs'] != null) {
        _sqlLogs.addAll(List<Map<String, dynamic>>.from(res['logs']));
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _isEditingTableDirectly = false;
      _editTableName = null;
      _editTablePKs.clear();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a single cell or row in editable grid
  Future<void> updateEditableGridRow(Map<String, dynamic> rowData, String columnName, dynamic newValue) async {
    if (_selectedDatabase == null || _editTableName == null) return;
    
    // Prepare primary key values for where clause
    Map<String, dynamic> pkValues = {};
    for (var pk in _editTablePKs) {
      if (!rowData.containsKey(pk)) {
        throw Exception("Row data is missing primary key field: $pk");
      }
      pkValues[pk] = rowData[pk];
    }

    // If there are no primary keys, we can't reliably update, throw error
    if (pkValues.isEmpty) {
      throw Exception("Cannot update row: Table does not have a primary key defined.");
    }

    Map<String, dynamic> updatedValues = {columnName: newValue};

    _isLoading = true;
    notifyListeners();

    try {
      final res = await _api.updateRow(_selectedDatabase!, _editTableName!, pkValues, updatedValues);
      
      // Update cell in our local _sqlResults to avoid full reload
      if (_sqlResults.isNotEmpty && _sqlResults[0]['rows'] != null) {
        final List<dynamic> rows = _sqlResults[0]['rows'];
        // Find row that matches PKs
        final rIdx = rows.indexWhere((r) {
          return _editTablePKs.every((pk) => r[pk] == rowData[pk]);
        });
        if (rIdx != -1) {
          rows[rIdx][columnName] = newValue;
        }
      }

      // Add log
      _sqlLogs.add({
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "query": res['query'],
        "status": "SUCCESS",
        "duration": "0.000s",
        "message": res['message']
      });

    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _sqlLogs.add({
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "query": "UPDATE `$_editTableName` ...",
        "status": "ERROR",
        "duration": "0.000s",
        "message": _errorMessage
      });
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Insert a new row in editable grid
  Future<void> insertEditableGridRow(Map<String, dynamic> values) async {
    if (_selectedDatabase == null || _editTableName == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final res = await _api.insertRow(_selectedDatabase!, _editTableName!, values);
      
      // Refresh the query to load auto-increment values and show correct rows
      String selectSql = "SELECT * FROM `$_editTableName`;";
      // Try to parse the original query inside editor if it had a WHERE clause
      final editRegExp = RegExp(r'^edit\s+([a-zA-Z0-9_`]+)(?:\s+where\s+(.+))?;?$', caseSensitive: false);
      final match = editRegExp.firstMatch(_sqlEditorText.trim());
      if (match != null && match.group(2) != null) {
        selectSql = "SELECT * FROM `$_editTableName` WHERE ${match.group(2)};";
      }

      final selectRes = await _api.runQueries(selectSql, overrideDb: _selectedDatabase);
      _sqlResults = List<Map<String, dynamic>>.from(selectRes['results'] ?? []);

      // Add log
      _sqlLogs.add({
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "query": res['query'],
        "status": "SUCCESS",
        "duration": "0.000s",
        "message": res['message']
      });

    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _sqlLogs.add({
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "query": "INSERT INTO `$_editTableName` ...",
        "status": "ERROR",
        "duration": "0.000s",
        "message": _errorMessage
      });
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addLogMessage(String message, {bool isError = false}) {
    _sqlLogs.add({
      "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
      "query": "System Message",
      "status": isError ? "ERROR" : "SUCCESS",
      "duration": "0s",
      "message": message
    });
    notifyListeners();
  }

  void clearLogs() {
    _sqlLogs.clear();
    notifyListeners();
  }

  Future<void> runBatchQueries(List<String> dbs, String sql) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final res = await _api.runBatchQueries(dbs, sql);
      if (res['logs'] != null) {
        _sqlLogs.addAll(List<Map<String, dynamic>>.from(res['logs']));
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getAutoBackupConfigs() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final configs = await _api.getAutoBackupConfigs();
      return configs;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveAutoBackupConfig(String dbName, String backupTime, int keepDays, bool isActive) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.saveAutoBackupConfig(dbName, backupTime, keepDays, isActive);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> backupNow(List<String> dbs, String dirName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.backupNow(dbs, dirName);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<String>> getBackupDirectories() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final dirs = await _api.getBackupDirectories();
      return dirs;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getBackupFiles(String dirName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final files = await _api.getBackupFiles(dirName);
      return files;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> restoreBackup(
    String dirName,
    List<String> files,
    Map<String, String> targetDatabases,
    bool cleanRestore,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.restoreBackup(dirName, files, targetDatabases, cleanRestore);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> copyDatabase(List<String> srcDbs, String targetDb) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.copyDatabase(srcDbs, targetDb);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }
}

// Simple helper to format time
class time {
  static String strftime(String format) {
    final now = DateTime.now();
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }
}
