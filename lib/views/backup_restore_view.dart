import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';

class BackupRestoreView extends StatefulWidget {
  const BackupRestoreView({Key? key}) : super(key: key);

  @override
  State<BackupRestoreView> createState() => _BackupRestoreViewState();
}

class _BackupRestoreViewState extends State<BackupRestoreView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 1 state
  final Set<String> _selectedDatabasesTab1 = {};
  String _searchQueryTab1 = '';
  final _searchControllerTab1 = TextEditingController();
  final _timeController = TextEditingController(text: '02:00');
  final _keepDaysController = TextEditingController(text: '7');
  bool _isActive = true;
  Map<String, String> _dbBackupTimes = {};

  // Tab 2 state
  List<String> _directories = [];
  String? _selectedDirectory;
  List<Map<String, dynamic>> _files = [];
  final Set<String> _selectedFiles = {};
  final Map<String, TextEditingController> _targetDbControllers = {};
  bool _cleanRestore = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBackupDirectories();
      _loadBackupConfigs();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchControllerTab1.dispose();
    _timeController.dispose();
    _keepDaysController.dispose();
    for (var controller in _targetDbControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBackupConfigs() async {
    final state = AppStateProvider.of(context);
    final configs = await state.getAutoBackupConfigs();
    final times = <String, String>{};
    for (var c in configs) {
      final db = c['db_name'] as String?;
      final time = c['backup_time'] as String?;
      final active = c['is_active'] as bool? ?? false;
      if (db != null && time != null && active) {
        times[db] = time;
      }
    }
    setState(() {
      _dbBackupTimes = times;
    });
  }

  Future<void> _loadBackupDirectories() async {
    final state = AppStateProvider.of(context);
    final dirs = await state.getBackupDirectories();
    setState(() {
      _directories = dirs;
      if (_directories.isNotEmpty && _selectedDirectory == null) {
        _selectedDirectory = _directories.first;
        _loadBackupFiles(_selectedDirectory!);
      }
    });
  }

  Future<void> _loadBackupFiles(String dir) async {
    final state = AppStateProvider.of(context);
    final files = await state.getBackupFiles(dir);
    setState(() {
      _files = files;
      _selectedFiles.clear();
      // Initialize text controllers for each file's target DB name
      for (var f in _files) {
        final filename = f['filename'] as String;
        final defaultDb = filename.replaceAll('.sql', '');
        if (!_targetDbControllers.containsKey(filename)) {
          _targetDbControllers[filename] = TextEditingController(text: defaultDb);
        }
      }
    });
  }

  void _saveAutoBackup(AppState state) async {
    if (_selectedDatabasesTab1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자동 백업을 설정할 데이터베이스를 선택하세요.')),
      );
      return;
    }

    final time = _timeController.text.trim();
    if (time.length != 5 || !time.contains(':')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 백업 시간 형식(HH:MM)을 입력하세요. 예: 02:00')),
      );
      return;
    }

    final keepDays = int.tryParse(_keepDaysController.text) ?? 7;

    int successCount = 0;
    for (var dbName in _selectedDatabasesTab1) {
      final ok = await state.saveAutoBackupConfig(dbName, time, keepDays, _isActive);
      if (ok) successCount++;
    }

    _loadBackupConfigs();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$successCount개 데이터베이스의 자동 백업 설정이 저장되었습니다.')),
    );
  }

  void _backupNow(AppState state) async {
    if (_selectedDatabasesTab1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지금 백업할 데이터베이스를 선택하세요.')),
      );
      return;
    }

    final dirController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('지금 백업', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: dirController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '백업 디렉토리명 입력',
              labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              hintText: '예: manual_20260628',
              hintStyle: TextStyle(color: Color(0xFF475569)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () async {
                final dirName = dirController.text.trim();
                if (dirName.isEmpty) return;
                Navigator.of(context).pop();

                final ok = await state.backupNow(_selectedDatabasesTab1.toList(), dirName);
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('백업 작업이 성공적으로 실행되었습니다.')),
                  );
                  _loadBackupDirectories();
                }
              },
              child: const Text('백업 실행'),
            ),
          ],
        );
      },
    );
  }

  void _restoreFile(AppState state, String filename) async {
    if (_selectedDirectory == null) return;
    
    final targetDb = _targetDbControllers[filename]?.text.trim() ?? '';
    if (targetDb.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복원할 대상 데이터베이스명을 입력하세요.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('백업 복원 확인', style: TextStyle(color: Colors.white)),
          content: Text(
            '선택한 백업 파일($filename)을 데이터베이스 `$targetDb`에 복원하시겠습니까?\n\n'
            '※ 복원 직전에 해당 대상 데이터베이스의 실시간 임시 백업본이 자동 생성됩니다.',
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
              child: const Text('복원 실행'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final ok = await state.restoreBackup(
        _selectedDirectory!,
        [filename],
        {filename: targetDb},
        _cleanRestore,
      );
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원이 안전하게 완료되었습니다.')),
        );
        state.refreshDatabases(); // Refresh sidebar lists
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('데이터베이스 백업 / 복구 관리', style: TextStyle(color: Colors.white, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: const Color(0xFF38BDF8),
          tabs: const [
            Tab(text: '자동 백업 및 즉시 백업'),
            Tab(text: '백업 파일 복원'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Configuration & Backup Now
          _buildAutoBackupTab(state),

          // Tab 2: Restore backups
          _buildRestoreTab(state),
        ],
      ),
    );
  }

  Widget _buildAutoBackupTab(AppState state) {
    final filteredDbs = state.databases
        .where((db) => db.toLowerCase().contains(_searchQueryTab1.toLowerCase()))
        .toList();

    final allSelected = filteredDbs.isNotEmpty &&
        filteredDbs.every((db) => _selectedDatabasesTab1.contains(db));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Side: Select databases
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
                controller: _searchControllerTab1,
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
                    _searchQueryTab1 = val;
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
                      _selectedDatabasesTab1.addAll(filteredDbs);
                    } else {
                      _selectedDatabasesTab1.removeAll(filteredDbs);
                    }
                  });
                },
              ),
              const Divider(color: Color(0xFF334155)),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredDbs.length,
                  itemBuilder: (context, idx) {
                    final db = filteredDbs[idx];
                    final isSelected = _selectedDatabasesTab1.contains(db);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(db, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13), overflow: TextOverflow.ellipsis),
                          ),
                          if (_dbBackupTimes.containsKey(db))
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4), width: 0.5),
                              ),
                              child: Text(
                                _dbBackupTimes[db]!,
                                style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      value: isSelected,
                      activeColor: const Color(0xFF6366F1),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedDatabasesTab1.add(db);
                          } else {
                            _selectedDatabasesTab1.remove(db);
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

        // Right Side: Configuration settings
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
                    '매일 자동 백업 예약 설정',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '선택한 데이터베이스들을 아래 설정한 시각에 매일 자동으로 백업 폴더(backup/날짜_시간)로 덤프합니다.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('백업 실행 시각 (HH:MM)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _timeController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '예: 02:00',
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('백업 보관 일수 (정수형)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _keepDaysController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '예: 7',
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('스케줄링 예약 활성화', style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: _isActive,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (val) {
                      setState(() {
                        _isActive = val;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: state.isLoading ? null : () => _saveAutoBackup(state),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('자동 백업 설정 저장'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF334155)),
                  const SizedBox(height: 16),
                  const Text(
                    '지금 즉시 수동 백업',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '선택한 데이터베이스들을 지금 즉시 특정 폴더명을 입력받아 백업 파일(DB명.sql)로 저장합니다.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: state.isLoading ? null : () => _backupNow(state),
                    icon: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.greenAccent),
                    label: const Text('지금 백업', style: TextStyle(color: Colors.greenAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.greenAccent),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestoreTab(AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown Selection for Directory
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              const Text('백업 폴더 선택: ', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDirectory,
                      dropdownColor: const Color(0xFF1E293B),
                      hint: const Text('선택...', style: TextStyle(color: Color(0xFF64748B))),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                      items: _directories.map((dir) {
                        return DropdownMenuItem<String>(
                          value: dir,
                          child: Text(dir),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedDirectory = val;
                          });
                          _loadBackupFiles(val);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
                onPressed: _loadBackupDirectories,
                tooltip: '목록 새로고침',
              )
            ],
          ),
        ),

        // Restore Options Mode Checkboxes
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              const Text('복원 옵션: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Row(
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: _cleanRestore,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (v) => setState(() => _cleanRestore = v ?? true),
                  ),
                  const Text('대상 DB를 초기화(삭제 후 재생성)하고 복원', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
              const SizedBox(width: 24),
              Row(
                children: [
                  Radio<bool>(
                    value: false,
                    groupValue: _cleanRestore,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (v) => setState(() => _cleanRestore = v ?? false),
                  ),
                  const Text('대상 DB의 기존 데이터와 병합하여 복원 (기존 유지)', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ),

        // Files Table list
        Expanded(
          child: _files.isEmpty
              ? const Center(
                  child: Text('백업된 SQL 파일이 없거나 폴더가 비어 있습니다.', style: TextStyle(color: Color(0xFF334155), fontSize: 13)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _files.length,
                  itemBuilder: (context, idx) {
                    final file = _files[idx];
                    final filename = file['filename'] as String;
                    final createTime = file['create_time'] ?? '-';
                    final size = file['size'] ?? 0;
                    final isChecked = _selectedFiles.contains(filename);

                    // Skip temporary restoration backups in this UI view to make it neat
                    if (filename.contains('.sql.202')) {
                      return const SizedBox.shrink();
                    }

                    return Card(
                      color: const Color(0xFF1E293B).withOpacity(0.5),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF334155))),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(filename, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  const SizedBox(height: 4),
                                  Text('파일 생성일: $createTime • 크기: ${(size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _targetDbControllers[filename],
                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                decoration: const InputDecoration(
                                  labelText: '복원할 DB명 입력',
                                  labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: !state.isLoading ? () => _restoreFile(state, filename) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFF334155),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              child: const Text('복원'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
