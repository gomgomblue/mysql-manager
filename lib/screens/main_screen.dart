import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';
import '../views/table_layout_view.dart';
import '../views/sql_editor_view.dart';
import '../views/batch_query_view.dart';
import '../views/backup_restore_view.dart';
import '../views/db_copy_view.dart';
import '../views/user_management_view.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep rich black-blue
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827), // Dark grey
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.storage_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'gomgom mysql',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 24),
            // Current DB Info chip
            if (state.currentConnection != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Text(
                  '연결됨: ${state.currentConnection!.host}',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          // Navigation tabs
          _buildNavTab(context, 'Table layout', '테이블 구조', Icons.schema_outlined),
          _buildNavTab(context, 'SQL Editor', 'SQL 에디터', Icons.code_rounded),
          const VerticalDivider(
            color: Color(0xFF374151),
            indent: 14,
            endIndent: 14,
            width: 24,
          ),
          // Logout menu in settings
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF9CA3AF)),
            color: const Color(0xFF1F2937),
            onSelected: (val) {
              if (val == 'logout') {
                _showLogoutConfirm(context, state);
              } else if (val == 'batch_query') {
                _showMaintenanceDialog(context, const BatchQueryView());
              } else if (val == 'backup_restore') {
                _showMaintenanceDialog(context, const BackupRestoreView());
              } else if (val == 'db_copy') {
                _showMaintenanceDialog(context, const DbCopyView());
              } else if (val == 'user_management') {
                _showMaintenanceDialog(context, const UserManagementView());
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('데이터베이스 관리', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const PopupMenuItem<String>(
                value: 'batch_query',
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('쿼리 일괄 실행', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'backup_restore',
                child: Row(
                  children: [
                    Icon(Icons.backup_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('백업 / 복원', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'db_copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_all_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('데이터베이스 복사', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'user_management',
                child: Row(
                  children: [
                    Icon(Icons.people_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('사용자 관리', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text('로그아웃 및 자동로그인 해제', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar (Database Tree)
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              border: Border(
                right: BorderSide(color: Color(0xFF1F2937), width: 1.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebarHeader(context, state),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    onChanged: (val) {
                      state.setSearchQuery(val);
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '데이터베이스 또는 테이블명, 필드명',
                      hintStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 14),
                      filled: true,
                      fillColor: const Color(0xFF1F2937),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF374151)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF374151)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: state.databases.isEmpty
                      ? const Center(
                          child: Text(
                            '데이터베이스를 찾을 수 없습니다.',
                            style: TextStyle(color: Color(0xFF4B5563)),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final query = state.searchQuery.toLowerCase();
                            final List<String> filteredDbs;
                            if (query.isEmpty) {
                              filteredDbs = state.databases;
                            } else {
                              final searchResultsDbs = state.searchResults.map((r) => r['database'] as String).toSet();
                              filteredDbs = state.databases.where((db) {
                                if (db.toLowerCase().contains(query)) return true;
                                if (searchResultsDbs.contains(db)) return true;
                                return false;
                              }).toList();
                            }

                            if (filteredDbs.isEmpty) {
                              return const Center(
                                child: Text(
                                  '검색 결과가 없습니다.',
                                  style: TextStyle(color: Color(0xFF4B5563), fontSize: 12),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: filteredDbs.length,
                              itemBuilder: (context, idx) {
                                final dbName = filteredDbs[idx];
                                return _buildDatabaseNode(context, state, dbName);
                              },
                            );
                          }
                        ),
                ),
              ],
            ),
          ),
          
          // Main Content View
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: Stack(
                children: [
                  _buildMainContent(state),
                  // General Error Banner
                  if (state.errorMessage != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.errorMessage!,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => state.clearErrorMessage(),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  
                  // Global Loading Overlay
                  if (state.isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.4),
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab(BuildContext context, String menuKey, String displayLabel, IconData icon) {
    final state = AppStateProvider.of(context);
    final isActive = state.activeMenu == menuKey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: () => state.changeMenu(menuKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF374151) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 8),
              Text(
                displayLabel,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF1F2937)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '데이터베이스',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF9CA3AF)),
            onPressed: () {
              state.refreshDatabases();
            },
            tooltip: '연결 및 데이터베이스 새로고침',
          )
        ],
      ),
    );
  }

  Widget _buildDatabaseNode(BuildContext context, AppState state, String dbName) {
    final query = state.searchQuery.toLowerCase();
    final hasMatchingTable = query.isNotEmpty && state.searchResults.any((r) => r['database'] == dbName);

    final isExpanded = state.expandedDatabases.contains(dbName) || hasMatchingTable;
    final isSelected = state.selectedDatabase == dbName;
    final showDeleteButtons = state.activeMenu == 'SQL Editor' || state.activeMenu.toLowerCase() == 'table layout';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Database Item
        InkWell(
          onTap: () {
            state.selectDatabase(dbName);
            state.toggleDatabaseExpanded(dbName);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: isSelected ? const Color(0xFF6366F1).withOpacity(0.15) : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 20,
                  color: const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.folder_rounded,
                  size: 16,
                  color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHighlightedText(
                    dbName,
                    state.searchQuery,
                    TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFD1D5DB),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (showDeleteButtons)
                  GestureDetector(
                    onTap: () {}, // Prevent propagation to parent InkWell
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                      onPressed: () => _confirmDropDatabase(context, state, dbName),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 16,
                      tooltip: '데이터베이스 삭제',
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Tables List inside expanded DB
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: state.tables.containsKey(dbName) || query.isNotEmpty
                ? Builder(
                    builder: (context) {
                      final List<String> filteredTables;
                      if (query.isEmpty) {
                        filteredTables = (state.tables[dbName] ?? []).toList();
                      } else {
                        filteredTables = state.searchResults
                            .where((r) => r['database'] == dbName)
                            .map((r) => r['table'] as String)
                            .toSet()
                            .toList();
                      }

                      if (filteredTables.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            '테이블이 없습니다',
                            style: TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: filteredTables.map((tableName) {
                          final isTableSelected = state.selectedDatabase == dbName && state.selectedTable == tableName;

                          return InkWell(
                            onTap: () async {
                              if (state.activeMenu == 'SQL Editor') {
                                await state.setupDirectTableEditing(tableName, database: dbName, limit: 100);
                              } else {
                                await state.selectTable(dbName, tableName);
                              }
                            },
                            onDoubleTap: () async {
                              await state.setupDirectTableEditing(tableName, database: dbName, limit: 100);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isTableSelected
                                    ? const Color(0xFF6366F1).withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.table_chart_outlined,
                                    size: 14,
                                    color: isTableSelected ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildHighlightedText(
                                      tableName,
                                      state.searchQuery,
                                      TextStyle(
                                        color: isTableSelected ? const Color(0xFF818CF8) : const Color(0xFF9CA3AF),
                                        fontSize: 12.5,
                                        fontWeight: isTableSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (showDeleteButtons)
                                    GestureDetector(
                                      onTap: () {}, // Prevent propagation
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 13, color: Colors.redAccent),
                                        onPressed: () => _confirmDropTable(context, state, dbName, tableName),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        splashRadius: 14,
                                        tooltip: '테이블 삭제',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildMainContent(AppState state) {

    if (state.selectedDatabase == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storage_rounded,
              size: 64,
              color: const Color(0xFF1E293B).withOpacity(0.8),
            ),
            const SizedBox(height: 16),
            const Text(
              '선택된 데이터베이스 없음',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '시작하려면 사이드바에서 데이터베이스와 테이블을 선택하세요.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (state.activeMenu == 'Table layout') {
      return const TableLayoutView();
    } else {
      return const SqlEditorView();
    }
  }

  void _showLogoutConfirm(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('연결을 종료하시겠습니까?', style: TextStyle(color: Colors.white)),
          content: const Text(
            '현재 연결된 MySQL 데이터베이스 연결을 해제하고 자동 로그인을 취소합니다.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                state.logout();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('로그아웃', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showMaintenanceDialog(BuildContext context, Widget view) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 1200,
            height: 800,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: view,
            ),
          ),
        );
      },
    );
  }
  Widget _buildHighlightedText(String text, String highlight, TextStyle normalStyle) {
    if (highlight.isEmpty) {
      return Text(text, style: normalStyle);
    }
    
    final textLower = text.toLowerCase();
    final highlightLower = highlight.toLowerCase();
    
    if (!textLower.contains(highlightLower)) {
      return Text(text, style: normalStyle);
    }
    
    final List<TextSpan> spans = [];
    int start = 0;
    int index = textLower.indexOf(highlightLower, start);
    
    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: normalStyle));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + highlight.length),
        style: normalStyle.copyWith(
          color: const Color(0xFF38BDF8), // Bright blue highlight color!
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + highlight.length;
      index = textLower.indexOf(highlightLower, start);
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: normalStyle));
    }
    
    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _confirmDropDatabase(BuildContext context, AppState state, String dbName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('데이터베이스 삭제', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '선택한 데이터베이스 [$dbName]을 삭제하시겠습니까?\n이 작업은 데이터베이스 안의 모든 테이블과 데이터를 영구히 제거합니다.',
            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('삭제 실행'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final success = await state.dropDatabase(dbName);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$dbName] 데이터베이스가 정상적으로 삭제되었습니다.')),
        );
      }
    }
  }

  Future<void> _confirmDropTable(BuildContext context, AppState state, String dbName, String tableName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('테이블 삭제', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '선택한 테이블 [$tableName]을 삭제하시겠습니까?\n이 작업은 테이블 구조와 모든 레코드를 영구히 제거합니다.',
            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('삭제 실행'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final success = await state.dropTable(dbName, tableName);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$tableName] 테이블이 정상적으로 삭제되었습니다.')),
        );
      }
    }
  }
}
