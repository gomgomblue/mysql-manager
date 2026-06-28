import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';
import '../widgets/sql_autocomplete_field.dart';

class SqlEditorView extends StatefulWidget {
  const SqlEditorView({Key? key}) : super(key: key);

  @override
  State<SqlEditorView> createState() => _SqlEditorViewState();
}

class _SqlEditorViewState extends State<SqlEditorView> {
  final _queryController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  
  // Local state to manage addition of new rows in editable grid
  final List<Map<String, dynamic>> _newRows = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync query controller with editor text from state (e.g., when edit table is clicked)
    final state = AppStateProvider.of(context);
    if (_queryController.text != state.sqlEditorText) {
      _queryController.text = state.sqlEditorText;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _runQueries(AppState state) {
    state.setSqlText(_queryController.text);
    state.runQueries(_queryController.text);
    setState(() {
      _newRows.clear(); // Clear any staged new rows when a new query is run
    });
    
    // Auto-scroll logs to bottom after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (!state.isLoading) {
            _runQueries(state);
          }
        },
      },
      child: Column(
        children: [
        // Editor Panel
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.keyboard_arrow_right_rounded, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 8),
                      Text(
                        state.selectedDatabase != null 
                          ? '현재 선택된 데이터베이스: `${state.selectedDatabase}`'
                          : '선택된 데이터베이스 없음',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (state.isEditingTableDirectly) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            state.runQueries("SELECT * FROM `${state.editTableName}`;");
                          },
                          icon: const Icon(Icons.close_rounded, size: 14, color: Colors.amberAccent),
                          label: const Text('편집 모드 종료', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.amberAccent),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Row(
                        children: [
                          Checkbox(
                            value: state.showQueryHistory,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) {
                              state.toggleShowQueryHistory();
                              if (state.showQueryHistory) {
                                state.fetchQueryHistory();
                              }
                            },
                          ),
                          const Text('히스토리', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                          const SizedBox(width: 16),
                        ],
                      ),
                       ElevatedButton.icon(
                        onPressed: state.isLoading ? null : () => _runQueries(state),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('실행 (F4)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Text Area
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: SqlAutocompleteField(
                  controller: _queryController,
                  maxLines: 8,
                  onChanged: (text) => state.setSqlText(text),
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    color: Color(0xFFE2E8F0),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText: '여기에 SQL 쿼리를 입력하세요. 여러 쿼리는 세미콜론(;)으로 구분합니다.\n예시: SELECT * FROM users;\n\n데이터 직접 편집: edit 테이블명 [where 조건절];',
                    hintStyle: const TextStyle(color: Color(0xFF475569)),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Workspace Grid & Logs Panel
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grid Results
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: _buildQueryResultSection(state),
                ),
              ),

              // Live Logs Window
              Expanded(
                flex: 1,
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
                              '실행 로그 창',
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
                                child: Text('기록된 로그가 없습니다.', style: TextStyle(color: Color(0xFF334155), fontSize: 12)),
                              )
                            : ListView.builder(
                                controller: _logScrollController,
                                padding: const EdgeInsets.all(12),
                                itemCount: state.sqlLogs.length,
                                itemBuilder: (context, idx) {
                                  final log = state.sqlLogs[idx];
                                  final isError = log['status'] == 'ERROR';
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
                                              '[${log['status']}]  ${log['timestamp']}',
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
              if (state.showQueryHistory)
                Container(
                  width: 320,
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
                    color: Color(0xFF111827),
                  ),
                  child: QueryHistoryPane(
                    onSelectQuery: (query) {
                      final text = _queryController.text;
                      final selection = _queryController.selection;
                      if (selection.isValid) {
                        final newText = text.replaceRange(selection.start, selection.end, query);
                        _queryController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                            offset: selection.start + query.length,
                          ),
                        );
                      } else {
                        _queryController.text = text + (text.isEmpty ? "" : "\n") + query;
                      }
                      state.setSqlText(_queryController.text);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildQueryResultSection(AppState state) {
    if (state.sqlResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 48, color: Color(0xFF1E293B)),
            SizedBox(height: 12),
            const Text('결과가 없습니다. 쿼리를 실행하여 데이터를 표시하세요.', style: TextStyle(color: Color(0xFF475569), fontSize: 13)),
          ],
        ),
      );
    }

    // Displays the first result in standard scrollable grid
    final firstResult = state.sqlResults[0];

    if (firstResult['success'] == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text('SQL 실행 실패', style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(
                firstResult['error'] ?? 'Unknown error occurred.',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (firstResult['type'] == 'write') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF34D399)),
            const SizedBox(height: 12),
            const Text('쿼리 실행 성공', style: TextStyle(color: Color(0xFF34D399), fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('영향을 받은 행 수: ${firstResult['affected_rows']}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
      );
    }

    final columns = List<String>.from(firstResult['columns'] ?? []);
    final rows = List<Map<String, dynamic>>.from(firstResult['rows'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Grid Toolbar (e.g., editable mode, add row button)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1E293B).withOpacity(0.4),
          child: Row(
            children: [
              Text(
                '그리드 뷰: ${rows.length}개 행 반환됨',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (state.isEditingTableDirectly) ...[
                // "+" Button to add row
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      // Create an empty map representing the new row
                      final emptyRow = <String, dynamic>{};
                      for (var col in columns) {
                        emptyRow[col] = '';
                      }
                      _newRows.add(emptyRow);
                    });
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('행 추가 (+)', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
              ]
            ],
          ),
        ),

        // Scrollable Grid Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: const Color(0xFF1E293B),
                ),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(const Color(0xFF1E293B)),
                  dataRowMinHeight: 46,
                  dataRowMaxHeight: 46,
                  // Add empty cell column for actions if in editable mode
                  columns: [
                    ...columns.map((colName) => DataColumn(
                      label: Text(
                        colName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    )),
                    if (state.isEditingTableDirectly)
                      const DataColumn(
                        label: Text(
                          '작업',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                  ],
                  rows: [
                    // Render existing rows
                    ...rows.map((row) {
                      return DataRow(
                        cells: [
                          ...columns.map((colName) {
                            final val = row[colName];
                            
                            if (state.isEditingTableDirectly) {
                              return DataCell(
                                EditableCell(
                                  value: val,
                                  onSave: (newValue) async {
                                    try {
                                      await state.updateEditableGridRow(row, colName, newValue);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('행이 성공적으로 수정되었습니다.'), duration: Duration(seconds: 1)),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  },
                                ),
                              );
                            }
                            
                            return DataCell(
                              Text(
                                val?.toString() ?? 'NULL',
                                style: TextStyle(
                                  color: val == null ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                                  fontSize: 13,
                                  fontStyle: val == null ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            );
                          }).toList(),
                          
                          if (state.isEditingTableDirectly)
                            DataCell(
                              const Text('-', style: TextStyle(color: Color(0xFF475569))),
                            ),
                        ],
                      );
                    }).toList(),

                    // Render staged new rows
                    ..._newRows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;

                      return DataRow(
                        color: MaterialStateProperty.all(Colors.green.withOpacity(0.05)),
                        cells: [
                          ...columns.map((colName) {
                            return DataCell(
                              TextField(
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  border: UnderlineInputBorder(),
                                ),
                                onChanged: (text) {
                                  row[colName] = text;
                                },
                              ),
                            );
                          }).toList(),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check, color: Colors.greenAccent, size: 18),
                                  onPressed: () async {
                                    try {
                                      await state.insertEditableGridRow(row);
                                      setState(() {
                                        _newRows.removeAt(idx); // Remove from new list since saved
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('행이 성공적으로 추가되었습니다.')),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  },
                                  tooltip: '행 저장 (Insert)',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _newRows.removeAt(idx);
                                    });
                                  },
                                  tooltip: '취소',
                                ),
                              ],
                            ),
                          )
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Inline Editable Cell Component
class EditableCell extends StatefulWidget {
  final dynamic value;
  final Function(dynamic newValue) onSave;

  const EditableCell({
    Key? key,
    required this.value,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<EditableCell> {
  bool _isEditing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _save();
      }
    });
  }

  @override
  void didUpdateWidget(covariant EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.value != oldWidget.value) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _isEditing = false;
    });
    // Triggers save callback
    if (_controller.text != widget.value?.toString()) {
      widget.onSave(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
        ),
        onSubmitted: (_) => _save(),
      );
    }

    return InkWell(
      onDoubleTap: () {
        setState(() {
          _isEditing = true;
        });
      },
      child: Container(
        width: double.infinity,
        alignment: Alignment.centerLeft,
        child: Text(
          widget.value?.toString() ?? 'NULL',
          style: TextStyle(
            color: widget.value == null ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
            fontSize: 13,
            fontStyle: widget.value == null ? FontStyle.italic : FontStyle.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class QueryHistoryPane extends StatefulWidget {
  final ValueChanged<String> onSelectQuery;

  const QueryHistoryPane({Key? key, required this.onSelectQuery}) : super(key: key);

  @override
  State<QueryHistoryPane> createState() => _QueryHistoryPaneState();
}

class _QueryHistoryPaneState extends State<QueryHistoryPane> {
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _keywordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    _startDateController.text = "${weekAgo.year}-${_twoDigits(weekAgo.month)}-${_twoDigits(weekAgo.day)}";
    _endDateController.text = "${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}";
  }

  String _twoDigits(int n) {
    if (n >= 10) return '$n';
    return '0$n';
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF1E293B),
          child: const Row(
            children: [
              Icon(Icons.history, color: Color(0xFF38BDF8), size: 16),
              SizedBox(width: 8),
              Text(
                '쿼리 실행 히스토리',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startDateController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: '시작 일자',
                        labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                        hintText: 'YYYY-MM-DD',
                        hintStyle: TextStyle(color: Color(0xFF475569), fontSize: 11),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _endDateController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: '종료 일자',
                        labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                        hintText: 'YYYY-MM-DD',
                        hintStyle: TextStyle(color: Color(0xFF475569), fontSize: 11),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keywordController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: '쿼리 키워드',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  hintText: '일부 키워드 검색',
                  hintStyle: TextStyle(color: Color(0xFF475569), fontSize: 11),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  state.fetchQueryHistory(
                    startDate: _startDateController.text.trim(),
                    endDate: _endDateController.text.trim(),
                    keyword: _keywordController.text.trim(),
                  );
                },
                icon: const Icon(Icons.search, size: 14),
                label: const Text('조회', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B), height: 1),
        Expanded(
          child: state.queryHistoryList.isEmpty
              ? const Center(
                  child: Text('히스토리 결과가 없습니다.', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
                )
              : ListView.builder(
                  itemCount: state.queryHistoryList.length,
                  itemBuilder: (context, index) {
                    final item = state.queryHistoryList[index];
                    final query = item['query_text'] as String? ?? '';
                    final executedAt = item['executed_at'] as String? ?? '';
                    final isSuccess = item['success'] == true;
                    final time = item['execution_time'] ?? 0.0;
                    final user = item['mysql_user'] ?? 'unknown';

                    return InkWell(
                      onTap: () => widget.onSelectQuery(query),
                      hoverColor: const Color(0xFF1E293B),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                                      size: 12,
                                      color: isSuccess ? Colors.green : Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isSuccess ? '성공' : '실패',
                                      style: TextStyle(
                                        color: isSuccess ? Colors.green : Colors.red,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${time.toStringAsFixed(3)}s • $user',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              query,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontFamily: 'Courier',
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              executedAt,
                              style: const TextStyle(color: Color(0xFF475569), fontSize: 9.5),
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
