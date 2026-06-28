import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({Key? key}) : super(key: key);

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  List<dynamic> _users = [];
  bool _loading = true;
  Map<String, dynamic>? _selectedUser;
  List<dynamic> _selectedUserGrants = [];
  bool _isSuperuser = false;

  // Form controllers
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hostController = TextEditingController();
  
  // Track database permissions for create/edit
  // Format: { dbName: { 'SELECT': true, 'INSERT': false, ... } }
  Map<String, Map<String, bool>> _dbGrantsMap = {};

  bool _isCreating = false;
  bool _isEditing = false;

  final List<String> _availablePrivileges = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _selectedUser = null;
      _isCreating = false;
      _isEditing = false;
      _isSuperuser = false;
    });

    final state = AppStateProvider.of(context);
    final list = await state.getUsers();
    setState(() {
      _users = list;
      _loading = false;
    });
  }

  Future<void> _loadUserDetail(Map<String, dynamic> userItem) async {
    setState(() {
      _loading = true;
      _selectedUser = userItem;
      _isCreating = false;
      _isEditing = false;
      _isSuperuser = false;
    });

    final state = AppStateProvider.of(context);
    final detail = await state.getUserDetail(userItem['user'], userItem['host']);
    setState(() {
      _selectedUserGrants = detail['grants'] ?? [];
      _isSuperuser = detail['superuser'] == true;
      _loading = false;
    });
  }

  void _prepareCreateForm() {
    final state = AppStateProvider.of(context);
    _usernameController.clear();
    _passwordController.clear();
    _hostController.text = '%'; // default host to wild-card
    _isSuperuser = false;

    // Initialize all databases with false privileges
    _dbGrantsMap = {};
    for (final db in state.databases) {
      _dbGrantsMap[db] = {
        for (final priv in _availablePrivileges) priv: false
      };
    }

    setState(() {
      _isCreating = true;
      _isEditing = false;
      _selectedUser = null;
    });
  }

  void _prepareEditForm() {
    if (_selectedUser == null) return;
    final state = AppStateProvider.of(context);
    
    _usernameController.text = _selectedUser!['user'];
    _passwordController.clear(); // Keep empty unless changing
    _hostController.text = _selectedUser!['host'];

    // Initialize all databases with false privileges first
    _dbGrantsMap = {};
    for (final db in state.databases) {
      _dbGrantsMap[db] = {
        for (final priv in _availablePrivileges) priv: false
      };
    }

    // Load active privileges with robust case-insensitive database matching
    if (!_isSuperuser) {
      for (final grant in _selectedUserGrants) {
        final dbName = grant['db'] as String? ?? '';
        final privList = List<String>.from(grant['privileges'] ?? []);
        
        String? matchedDbKey;
        for (final dbKey in _dbGrantsMap.keys) {
          if (dbKey.toLowerCase() == dbName.toLowerCase()) {
            matchedDbKey = dbKey;
            break;
          }
        }

        if (matchedDbKey != null) {
          for (final priv in privList) {
            final upperPriv = priv.toUpperCase();
            if (_dbGrantsMap[matchedDbKey]!.containsKey(upperPriv)) {
              _dbGrantsMap[matchedDbKey]![upperPriv] = true;
            }
          }
        }
      }
    }

    setState(() {
      _isEditing = true;
      _isCreating = false;
    });
  }

  List<Map<String, dynamic>> _collectGrants() {
    List<Map<String, dynamic>> list = [];
    _dbGrantsMap.forEach((dbName, privMap) {
      List<String> activePrivs = [];
      privMap.forEach((priv, active) {
        if (active) activePrivs.add(priv);
      });
      if (activePrivs.isNotEmpty) {
        list.add({
          'db': dbName,
          'privileges': activePrivs,
        });
      }
    });
    return list;
  }

  Future<void> _submitCreate() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _hostController.text.trim();

    if (username.isEmpty || host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자명과 호스트/IP를 입력해 주세요.')),
      );
      return;
    }

    final state = AppStateProvider.of(context);
    final grants = _isSuperuser ? <Map<String, dynamic>>[] : _collectGrants();

    final ok = await state.createUser(username, password, host, _isSuperuser, grants);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 사용자가 정상적으로 생성되었습니다.')),
      );
      _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사용자 생성 실패: ${state.errorMessage}')),
      );
    }
  }

  Future<void> _submitUpdate() async {
    if (_selectedUser == null) return;
    
    final username = _selectedUser!['user'];
    final oldHost = _selectedUser!['host'];
    final newHost = _hostController.text.trim();
    final password = _passwordController.text;

    if (newHost.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('호스트/IP는 필수 입력 값입니다.')),
      );
      return;
    }

    final state = AppStateProvider.of(context);
    final grants = _isSuperuser ? <Map<String, dynamic>>[] : _collectGrants();

    final ok = await state.updateUser(username, oldHost, newHost, password, _isSuperuser, grants);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자 정보가 안전하게 수정되었습니다.')),
      );
      _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사용자 수정 실패: ${state.errorMessage}')),
      );
    }
  }

  Future<void> _deleteUser() async {
    if (_selectedUser == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('사용자 삭제', style: TextStyle(color: Colors.white)),
          content: Text(
            '정말로 `${_selectedUser!['user']}`@`${_selectedUser!['host']}` 사용자를 완전히 삭제하시겠습니까?\n이 작업은 취소할 수 없습니다.',
            style: const TextStyle(color: Color(0xFFE2E8F0)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final state = AppStateProvider.of(context);
      final ok = await state.deleteUser(_selectedUser!['user'], _selectedUser!['host']);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자가 안전하게 삭제되었습니다.')),
        );
        _loadUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사용자 삭제 실패: ${state.errorMessage}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 950,
      height: 650,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar: Users list
          Container(
            width: 320,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFF334155), width: 1.5)),
              color: Color(0xFF0F172A),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with back button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  color: const Color(0xFF1E293B),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '닫기',
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.people_rounded, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        '등록된 사용자 목록',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                
                // User List
                Expanded(
                  child: _loading && _users.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                      : _users.isEmpty
                          ? const Center(child: Text('등록된 사용자가 없습니다.', style: TextStyle(color: Color(0xFF475569))))
                          : ListView.builder(
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final userItem = _users[index];
                                final isSelected = _selectedUser != null &&
                                    _selectedUser!['user'] == userItem['user'] &&
                                    _selectedUser!['host'] == userItem['host'];
                                return InkWell(
                                  onTap: () => _loadUserDetail(userItem),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF334155).withOpacity(0.4) : Colors.transparent,
                                      border: const Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person_outline_rounded,
                                          size: 16,
                                          color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '${userItem['user']}@${userItem['host']}',
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                              fontSize: 12.5,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontFamily: 'Courier',
                                            ),
                                          ),
                                        ),
                                        Icon(Icons.chevron_right, size: 14, color: const Color(0xFF475569)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                const Divider(color: Color(0xFF334155), height: 1),

                // Footer add user button
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: _prepareCreateForm,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                    label: const Text('신규 사용자 추가', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right Panel: Details or Form
          Expanded(
            child: Container(
              color: const Color(0xFF0B0F19),
              child: _buildRightPanelContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanelContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
    }

    if (_isCreating || _isEditing) {
      return _buildFormPanel();
    }

    if (_selectedUser != null) {
      return _buildDetailPanel();
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_box_outlined, size: 64, color: Color(0xFF1E293B)),
          SizedBox(height: 12),
          Text(
            '조회할 사용자를 선택하거나 신규 사용자를 생성하세요.',
            style: TextStyle(color: Color(0xFF475569), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '상세 정보: ${_selectedUser!['user']}@${_selectedUser!['host']}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _prepareEditForm,
                    icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('권한 및 비번 수정', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _deleteUser,
                    icon: const Icon(Icons.delete_forever_rounded, size: 14),
                    label: const Text('사용자 삭제', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '데이터베이스별 권한 현황',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                _isSuperuser
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.shield_outlined, color: Color(0xFF818CF8), size: 18),
                            SizedBox(width: 8),
                            Text(
                              '이 사용자는 모든 권한을 가진 [슈퍼유저]입니다.',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : _selectedUserGrants.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Color(0xFF64748B), size: 16),
                                SizedBox(width: 8),
                                Text(
                                  '이 사용자에게 직접 부여된 데이터베이스 수준 권한이 없습니다.',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _selectedUserGrants.length,
                            itemBuilder: (context, index) {
                              final grant = _selectedUserGrants[index];
                              final dbName = grant['db'] as String;
                              final privList = List<String>.from(grant['privileges'] ?? []);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.storage, size: 16, color: Colors.amber),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            dbName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: privList.map((priv) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                                                ),
                                                child: Text(
                                                  priv,
                                                  style: const TextStyle(
                                                    color: Color(0xFF818CF8),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel() {
    final titleText = _isCreating ? '신규 사용자 추가' : '사용자 정보 및 권한 수정';
    final actionText = _isCreating ? '추가 실행' : '저장 완료';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isCreating ? Icons.person_add_alt_1_rounded : Icons.edit_note_rounded,
                    color: const Color(0xFF38BDF8),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    titleText,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isCreating = false;
                        _isEditing = false;
                      });
                      if (_selectedUser != null) {
                        _loadUserDetail(_selectedUser!);
                      }
                    },
                    child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isCreating ? _submitCreate : _submitUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text(actionText),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Form Fields and Grants Selection
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('사용자명', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _usernameController,
                            enabled: _isCreating, // Username is key, cannot edit
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'ex) app_user',
                              hintStyle: const TextStyle(color: Color(0xFF475569)),
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                              fillColor: _isCreating ? Colors.transparent : const Color(0xFF1E293B),
                              filled: !_isCreating,
                              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              disabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1E293B))),
                              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('비밀번호', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: _isCreating ? '비밀번호 입력' : '비밀번호 미입력시 유지',
                              hintStyle: const TextStyle(color: Color(0xFF475569)),
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('허용 호스트 / IP', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _hostController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'ex) %, localhost, 192.168.0.100',
                              hintStyle: TextStyle(color: Color(0xFF475569)),
                              isDense: true,
                              contentPadding: EdgeInsets.all(12),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                // Superuser Checkbox block
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isSuperuser ? const Color(0xFF6366F1).withOpacity(0.1) : const Color(0xFF1E293B).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isSuperuser ? const Color(0xFF6366F1).withOpacity(0.4) : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '슈퍼유저 (Superuser)',
                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '활성화 시 모든 데이터베이스에 대한 관리 및 접근 권한(ALL PRIVILEGES)이 부여됩니다.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _isSuperuser,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (val) {
                            setState(() {
                              _isSuperuser = val ?? false;
                              if (_isSuperuser) {
                                // DB별 권한 체크박스는 모두 해제
                                for (final dbName in _dbGrantsMap.keys) {
                                  for (final priv in _availablePrivileges) {
                                    _dbGrantsMap[dbName]![priv] = false;
                                  }
                                }
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 12),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '데이터베이스별 권한 부여 설정',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    // Select/Deselect ALL Databases privileges button
                    ElevatedButton.icon(
                      onPressed: _isSuperuser
                          ? null
                          : () {
                              setState(() {
                                // Check if ALL privileges for ALL databases are currently true
                                bool allSelected = true;
                                for (final dbPrivs in _dbGrantsMap.values) {
                                  if (!dbPrivs.values.every((v) => v)) {
                                    allSelected = false;
                                    break;
                                  }
                                }
                                
                                // Toggle all
                                for (final dbName in _dbGrantsMap.keys) {
                                  for (final priv in _availablePrivileges) {
                                    _dbGrantsMap[dbName]![priv] = !allSelected;
                                  }
                                }
                              });
                            },
                      icon: const Icon(Icons.select_all_rounded, size: 14),
                      label: const Text('모든 데이터베이스 전체선택/해제', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: _isSuperuser ? const Color(0xFF475569) : const Color(0xFF38BDF8),
                        side: BorderSide(color: _isSuperuser ? const Color(0xFF1E293B) : const Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '접근 권한을 부여하고 싶은 데이터베이스의 각 체크박스를 선택하세요.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
                const SizedBox(height: 16),

                // DB Grants check Grid
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _dbGrantsMap.keys.length,
                  itemBuilder: (context, index) {
                    final dbName = _dbGrantsMap.keys.elementAt(index);
                    final privMap = _dbGrantsMap[dbName]!;

                    return Opacity(
                      opacity: _isSuperuser ? 0.4 : 1.0,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.storage, size: 14, color: Colors.amber),
                                const SizedBox(width: 8),
                                Text(
                                  dbName,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                // Quick select ALL
                                TextButton(
                                  onPressed: _isSuperuser
                                      ? null
                                      : () {
                                          setState(() {
                                            final allSelected = privMap.values.every((v) => v);
                                            for (final priv in _availablePrivileges) {
                                              privMap[priv] = !allSelected;
                                            }
                                          });
                                        },
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 24)),
                                  child: Text(
                                    '전체선택',
                                    style: TextStyle(
                                      color: _isSuperuser ? const Color(0xFF475569) : const Color(0xFF38BDF8),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: _availablePrivileges.map((priv) {
                                final active = _isSuperuser ? false : (privMap[priv] ?? false);
                                return InkWell(
                                  onTap: _isSuperuser
                                      ? null
                                      : () {
                                          setState(() {
                                            privMap[priv] = !active;
                                          });
                                        },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Checkbox(
                                          value: active,
                                          activeColor: const Color(0xFF6366F1),
                                          onChanged: _isSuperuser
                                              ? null
                                              : (val) {
                                                  setState(() {
                                                    privMap[priv] = val ?? false;
                                                  });
                                                },
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        priv,
                                        style: TextStyle(
                                          color: active ? Colors.white : const Color(0xFF64748B),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
