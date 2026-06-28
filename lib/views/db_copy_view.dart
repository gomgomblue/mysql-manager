import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';

class DbCopyView extends StatefulWidget {
  const DbCopyView({Key? key}) : super(key: key);

  @override
  State<DbCopyView> createState() => _DbCopyViewState();
}

class _DbCopyViewState extends State<DbCopyView> {
  final Set<String> _selectedDatabases = {};
  String _searchQuery = '';
  final _searchController = TextEditingController();
  String? _targetDatabase;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyDatabase(AppState state) async {
    if (_selectedDatabases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복사할 원본 데이터베이스를 선택하세요.')),
      );
      return;
    }
    if (_targetDatabase == null || _targetDatabase!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('데이터를 복사해 넣을 대상 데이터베이스를 선택하세요.')),
      );
      return;
    }

    if (_selectedDatabases.contains(_targetDatabase)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('원본 데이터베이스와 대상 데이터베이스는 다르게 지정해야 합니다.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('데이터베이스 복사 확인', style: TextStyle(color: Colors.white)),
          content: Text(
            '선택한 원본 ${_selectedDatabases.join(", ")}를 대상 `$_targetDatabase` 데이터베이스로 복사하시겠습니까?\n\n'
            '※ 주의: 대상 데이터베이스의 기존 구조와 데이터는 삭제되고 복제됩니다.\n'
            '※ 복제 실행 직전에 대상 데이터베이스의 백업본이 `backup/copy_backup/` 폴더 하위에 자동 백업됩니다.',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              child: const Text('복사 실행'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final ok = await state.copyDatabase(_selectedDatabases.toList(), _targetDatabase!);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('데이터베이스 복사가 안전하게 완료되었습니다.')),
        );
        state.refreshDatabases(); // Refresh sidebar lists
      }
    }
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
        title: const Text('데이터베이스 복사 (DB Cloner)', style: TextStyle(color: Colors.white, fontSize: 16)),
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
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
                const SizedBox(height: 12),
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

          // Right Side: Target DB Selector & Actions
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '대상 데이터베이스 선택 및 복제 실행',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '선택한 원본 데이터베이스들의 스키마 구조, 테이블, 인덱스, 레코드, 루틴(프로시저/함수)을 아래 선택한 대상 데이터베이스로 그대로 복제합니다.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '복제하여 데이터를 붙여넣을 대상 데이터베이스(Target DB)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _targetDatabase,
                          dropdownColor: const Color(0xFF1E293B),
                          hint: const Text('대상 데이터베이스 선택...', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                          items: state.databases.map((db) {
                            return DropdownMenuItem<String>(
                              value: db,
                              child: Text(db),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _targetDatabase = val;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: state.isLoading ? null : () => _copyDatabase(state),
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: const Text('복사 실행 (Copy Database)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('💡 복제 프로세스 안내', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                            '1. 복제 실행 직전에 대상(Target) 데이터베이스의 기존 데이터를 보호하기 위해 backup/copy_backup/ 폴더 하위에 [DB명.sql.시간] 임시 백업본이 자동 생성됩니다.\n'
                            '2. 이후 대상 데이터베이스가 초기화되고 원본(Source) 데이터베이스들로부터 추출한 SQL 덤프 파일이 주입되어 최종 복사가 완료됩니다.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
