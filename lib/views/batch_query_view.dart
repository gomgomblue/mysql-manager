import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';
import '../widgets/sql_autocomplete_field.dart';

class BatchQueryView extends StatefulWidget {
  const BatchQueryView({Key? key}) : super(key: key);

  @override
  State<BatchQueryView> createState() => _BatchQueryViewState();
}

class _BatchQueryViewState extends State<BatchQueryView> {
  final _queryController = TextEditingController();
  final _searchController = TextEditingController();
  final Set<String> _selectedDatabases = {};
  String _searchQuery = '';

  @override
  void dispose() {
    _queryController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _runBatchQueries(AppState state) async {
    if (_selectedDatabases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('쿼리를 실행할 데이터베이스를 선택하세요.')),
      );
      return;
    }
    if (_queryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('실행할 SQL 쿼리를 입력하세요.')),
      );
      return;
    }

    await state.runBatchQueries(_selectedDatabases.toList(), _queryController.text);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('일괄 쿼리 실행이 종료되었습니다. 로그를 확인하세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final theme = Theme.of(context);

    final filteredDatabases = state.databases
        .where((db) => db.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    final allSelected = filteredDatabases.isNotEmpty &&
        filteredDatabases.every((db) => _selectedDatabases.contains(db));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('쿼리 일괄 실행 (Batch Query)', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar: DB Selector
          Container(
            width: 320,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search Input
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '데이터베이스 검색...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 16),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Select All Checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('전체 선택', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  value: allSelected,
                  activeColor: const Color(0xFF6366F1),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedDatabases.addAll(filteredDatabases);
                      } else {
                        _selectedDatabases.removeAll(filteredDatabases);
                      }
                    });
                  },
                ),
                const Divider(color: Color(0xFF334155)),

                // DB Checkbox List
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredDatabases.length,
                    itemBuilder: (context, idx) {
                      final db = filteredDatabases[idx];
                      final isSelected = _selectedDatabases.contains(db);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(db, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13)),
                        value: isSelected,
                        activeColor: const Color(0xFF6366F1),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedDatabases.add(db);
                            } else {
                              _selectedDatabases.remove(db);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right Side: SQL Editor & Result Logs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // SQL Editor Panel
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF1E293B).withOpacity(0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'SQL 일괄 실행기 (선택된 DB에 순차 실행)',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: state.isLoading ? null : () => _runBatchQueries(state),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('일괄 실행'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: SqlAutocompleteField(
                          controller: _queryController,
                          maxLines: 6,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            height: 1.4,
                          ),
                          decoration: const InputDecoration(
                            hintText: '일괄 실행할 SQL 쿼리를 입력하세요. 세미콜론(;)으로 구분 가능합니다.\n예시: CREATE TABLE IF NOT EXISTS test_table (id INT);\n      INSERT INTO test_table VALUES (1);',
                            hintStyle: TextStyle(color: Color(0xFF475569)),
                            contentPadding: EdgeInsets.all(16),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Batch Logs Panel
                Expanded(
                  child: Container(
                    color: const Color(0xFF0B0F19),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: const Color(0xFF111827),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '실행 로그 내역 (로그 윈도우)',
                                style: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              TextButton(
                                onPressed: () => state.clearLogs(),
                                child: const Text('지우기', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              )
                            ],
                          ),
                        ),
                        Expanded(
                          child: state.sqlLogs.isEmpty
                              ? const Center(
                                  child: Text('실행 내역이 없습니다.', style: TextStyle(color: Color(0xFF334155), fontSize: 12)),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: state.sqlLogs.length,
                                  itemBuilder: (context, idx) {
                                    final log = state.sqlLogs[idx];
                                    final isError = log['status'] == 'ERROR';
                                    final dbName = log['database'] ?? '-';
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isError 
                                          ? Colors.redAccent.withOpacity(0.05) 
                                          : const Color(0xFF1E293B).withOpacity(0.3),
                                        border: Border.all(
                                          color: isError 
                                            ? Colors.redAccent.withOpacity(0.15) 
                                            : const Color(0xFF334155).withOpacity(0.3),
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '[DB: $dbName] [${log['status']}] ${log['timestamp']}',
                                                style: TextStyle(
                                                  color: isError ? Colors.redAccent : const Color(0xFF34D399),
                                                  fontFamily: 'Courier',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                log['duration'] ?? '',
                                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            log['query'] ?? '',
                                            style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'Courier', fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            log['message'] ?? '',
                                            style: TextStyle(
                                              color: isError ? Colors.redAccent.withOpacity(0.8) : const Color(0xFF94A3B8),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
