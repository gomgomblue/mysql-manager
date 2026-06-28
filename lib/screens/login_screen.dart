import 'package:flutter/material.dart';
import '../models/db_connection.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';
import '../services/storage_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '3306');
  final _userController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  final _databaseController = TextEditingController();

  bool _rememberConnection = true;
  bool _autoLoginEnabled = false;
  List<DbConnection> _history = [];
  DbConnection? _selectedHistoryItem;

  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _checkAutoLogin();
  }

  Future<void> _loadHistory() async {
    final list = await _storage.loadHistory();
    setState(() {
      _history = list;
    });
  }

  Future<void> _checkAutoLogin() async {
    final autoConn = await _storage.getAutoLoginConnection();
    if (autoConn != null && mounted) {
      final state = AppStateProvider.of(context);
      state.autoConnect(autoConn);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    super.dispose();
  }

  void _applyHistoryItem(DbConnection item) {
    setState(() {
      _selectedHistoryItem = item;
      _hostController.text = item.host;
      _portController.text = item.port.toString();
      _userController.text = item.user;
      _passwordController.text = item.password;
      _databaseController.text = item.database ?? '';
    });
  }

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final conn = DbConnection(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 3306,
      user: _userController.text.trim(),
      password: _passwordController.text,
      database: _databaseController.text.trim().isEmpty ? null : _databaseController.text.trim(),
    );

    final state = AppStateProvider.of(context);
    try {
      await state.connect(conn, _rememberConnection, _autoLoginEnabled);
      // Connection success is handled by state changing and rebuilding main app entry
    } catch (e) {
      // Error displayed in UI via state.errorMessage
    }
    _loadHistory(); // Reload history after connection attempt
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F172A), // Slate 900
              const Color(0xFF1E1B4B), // Indigo 950
              const Color(0xFF020617), // Black
            ],
            stops: const [0.1, 0.6, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(40),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.4), // Slate 800 with transparency
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF475569).withOpacity(0.3), // Slate 600 border
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Logo / Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo to Purple
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.storage_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            'gomgom mysql',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'MySQL 데이터베이스 관리 클라이언트',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF94A3B8), // Slate 400
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Connection History Dropdown
                    if (_history.isNotEmpty) ...[
                      Text(
                        '저장된 연결 목록',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF38BDF8), // Sky 400
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DbConnection>(
                            value: _selectedHistoryItem,
                            dropdownColor: const Color(0xFF1E293B),
                            hint: const Text(
                              '저장된 연결 정보를 선택하세요...',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                            isExpanded: true,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                            items: _history.map((item) {
                              return DropdownMenuItem<DbConnection>(
                                value: item,
                                child: Row(
                                  children: [
                                    const Icon(Icons.dns_outlined, size: 16, color: Color(0xFF8B5CF6)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                      onPressed: () async {
                                        await _storage.deleteFromHistory(item);
                                        _loadHistory();
                                        if (_selectedHistoryItem == item) {
                                          setState(() {
                                            _selectedHistoryItem = null;
                                          });
                                        }
                                      },
                                    )
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (item) {
                              if (item != null) {
                                _applyHistoryItem(item);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Text(
                      '연결 설정 정보',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF38BDF8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Host & Port Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            controller: _hostController,
                            label: '호스트 주소 (Host IP)',
                            hint: '127.0.0.1 또는 localhost',
                            icon: Icons.link_rounded,
                            validator: (v) => v!.isEmpty ? '호스트 주소를 입력해주세요' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(
                            controller: _portController,
                            label: '포트 (Port)',
                            hint: '3306',
                            icon: null,
                            keyboardType: TextInputType.number,
                            validator: (v) => v!.isEmpty ? '필수' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // User & Password Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _userController,
                            label: '사용자 계정 (Username)',
                            hint: 'root',
                            icon: Icons.person_rounded,
                            validator: (v) => v!.isEmpty ? '계정을 입력해주세요' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _passwordController,
                            label: '비밀번호 (Password)',
                            hint: '••••••••',
                            icon: Icons.vpn_key_rounded,
                            obscureText: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Default Database (Optional)
                    _buildTextField(
                      controller: _databaseController,
                      label: '기본 데이터베이스 (선택사항)',
                      hint: 'database_name',
                      icon: Icons.folder_open_rounded,
                    ),
                    const SizedBox(height: 16),

                    // Settings checkboxes
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '연결 정보 저장',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                            value: _rememberConnection,
                            activeColor: const Color(0xFF6366F1),
                            checkColor: Colors.white,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (val) {
                              setState(() {
                                _rememberConnection = val ?? false;
                                if (!_rememberConnection) {
                                  _autoLoginEnabled = false;
                                }
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '자동 로그인',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                            value: _autoLoginEnabled,
                            activeColor: const Color(0xFF6366F1),
                            checkColor: Colors.white,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: _rememberConnection
                                ? (val) {
                                    setState(() {
                                      _autoLoginEnabled = val ?? false;
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Error Message
                    if (state.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4),
                              ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                              onPressed: () => state.clearErrorMessage(),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Login Button
                    ElevatedButton(
                      onPressed: state.isLoading ? null : _handleConnect,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF6366F1).withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: state.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              '데이터베이스 연결',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF475569)),
            prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF64748B), size: 18) : null,
            filled: true,
            fillColor: const Color(0xFF0F172A).withOpacity(0.6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.6)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
