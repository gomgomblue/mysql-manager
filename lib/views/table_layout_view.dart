import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';
import '../services/code_generator.dart';

class TableLayoutView extends StatefulWidget {
  const TableLayoutView({Key? key}) : super(key: key);

  @override
  State<TableLayoutView> createState() => _TableLayoutViewState();
}

class _TableLayoutViewState extends State<TableLayoutView> {
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final theme = Theme.of(context);

    if (state.selectedTable == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          title: const Text('테이블 구조', style: TextStyle(color: Colors.white, fontSize: 16)),
          actions: [
            _buildCreateTableButton(context, state),
            const SizedBox(width: 16),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.table_rows_rounded,
                size: 64,
                color: const Color(0xFF334155).withOpacity(0.8),
              ),
              const SizedBox(height: 16),
              const Text(
                '선택된 테이블 없음',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '시작하려면 사이드바에서 테이블을 선택하거나 상단의 "테이블 생성"을 클릭하세요.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final originalCols = state.tableColumns;
    final visibleCols = state.visibleColumns;

    // Identify dropped columns
    final List<Map<String, dynamic>> droppedCols = [];
    for (var change in state.stagedChanges) {
      if (change['action'] == 'drop_column') {
        final droppedName = change['field_name'];
        final original = originalCols.firstWhere(
          (c) => c['field_name'] == droppedName,
          orElse: () => <String, dynamic>{},
        );
        if (original.isNotEmpty) {
          droppedCols.add(original);
        }
      }
    }

    // Combine active visible columns and dropped columns for full staged view
    final List<Map<String, dynamic>> allDisplayCols = [...visibleCols];
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.selectedTable!,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '스키마 관리자 • 데이터베이스: ${state.selectedDatabase}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ],
        ),
        actions: [
          // Table Management
          PopupMenuButton<String>(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.layers_outlined, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('테이블 관리', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                ],
              ),
            ),
            color: const Color(0xFF1E293B),
            onSelected: (val) => _handleTableManagement(context, state, val),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'create_table',
                child: Row(
                  children: [
                    Icon(Icons.add_box_outlined, color: Colors.greenAccent, size: 16),
                    SizedBox(width: 8),
                    Text('테이블 생성', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'drop_table',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_outlined, color: Colors.redAccent, size: 16),
                    SizedBox(width: 8),
                    Text('테이블 삭제', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'create_index',
                child: Row(
                  children: [
                    Icon(Icons.explore_outlined, color: Colors.lightBlueAccent, size: 16),
                    SizedBox(width: 8),
                    Text('인덱스 생성', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Auto Generation
          PopupMenuButton<String>(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('자동 생성', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                ],
              ),
            ),
            color: const Color(0xFF1E293B),
            onSelected: (val) => _handleAutoGeneration(context, state, val),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'sql_create_table', child: Text('Create table 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'sql_alter_add', child: Text('alter table add 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'sql_drop_table', child: Text('drop table 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'sql_insert', child: Text('insert into 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'sql_update', child: Text('update set 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'sql_upsert', child: Text('upsert 쿼리', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'obj_flutter', child: Text('flutter 객체', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'obj_go', child: Text('go 객체', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'obj_python', child: Text('python 객체', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'obj_delphi', child: Text('delphi 객체', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Staged Changes Banner
          if (state.stagedChanges.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF1E1B4B), // Deep indigo
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF818CF8)),
                  const SizedBox(width: 12),
                  Text(
                    '대기 중인 변경사항이 ${state.stagedChanges.length}개 있습니다.',
                    style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => state.clearStagedChanges(),
                    child: const Text('변경 취소', style: TextStyle(color: Color(0xFFFDA4AF))),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _confirmSaveStagedChanges(context, state),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('변경 저장'),
                  ),
                ],
              ),
            ),

          // Column headers description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '테이블 컬럼 구조',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showColumnDialog(context, state),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('컬럼 추가', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981), // Emerald
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                )
              ],
            ),
          ),

          // Scrollable Grid of columns
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2), // Comment
                    1: FlexColumnWidth(2), // Field Name
                    2: FlexColumnWidth(2), // Type
                    3: FlexColumnWidth(1), // Size
                    4: FlexColumnWidth(1), // Scale
                    5: FixedColumnWidth(60), // PK
                    6: FixedColumnWidth(60), // AI
                    7: FixedColumnWidth(90), // Actions
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header Row
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      children: [
                        _buildHeaderCell('설명(Comment)'),
                        _buildHeaderCell('필드명'),
                        _buildHeaderCell('데이터 타입'),
                        _buildHeaderCell('길이/크기'),
                        _buildHeaderCell('소수점'),
                        _buildHeaderCell('기본키(PK)'),
                        _buildHeaderCell('자동증가(AI)'),
                        _buildHeaderCell('작업'),
                      ],
                    ),

                    // Display active columns
                    ...allDisplayCols.map((col) {
                      final name = col['field_name'];
                      
                      // Check staging status
                      bool isNew = !originalCols.any((c) => c['field_name'] == name);
                      bool isModified = false;
                      if (!isNew) {
                        final orig = originalCols.firstWhere((c) => c['field_name'] == name);
                        isModified = col['data_type'] != orig['data_type'] ||
                            col['data_size']?.toString() != orig['data_size']?.toString() ||
                            col['decimal_places']?.toString() != orig['decimal_places']?.toString() ||
                            col['is_pk'] != orig['is_pk'] ||
                            col['is_ai'] != orig['is_ai'] ||
                            col['comment'] != orig['comment'];
                      }

                      Color rowColor = Colors.transparent;
                      if (isNew) {
                        rowColor = Colors.green.withOpacity(0.08);
                      } else if (isModified) {
                        rowColor = Colors.amber.withOpacity(0.08);
                      }

                      return TableRow(
                        decoration: BoxDecoration(
                          color: rowColor,
                          border: const Border(bottom: BorderSide(color: Color(0xFF334155))),
                        ),
                        children: [
                          _buildCommentCell(col['comment'] ?? '', isNew: isNew, isModified: isModified),
                          _buildTextCell(context, name, isNew: isNew, isModified: isModified, isBold: true),
                          _buildTextCell(context, col['data_type'], isNew: isNew, isModified: isModified),
                          _buildTextCell(context, col['data_size']?.toString() ?? '-', isNew: isNew, isModified: isModified),
                          _buildTextCell(context, col['decimal_places']?.toString() ?? '-', isNew: isNew, isModified: isModified),
                          _buildBooleanCell(col['is_pk'] == true),
                          _buildBooleanCell(col['is_ai'] == true),
                          _buildActionsCell(context, state, col, isNew),
                        ],
                      );
                    }).toList(),

                    // Display dropped columns as strikethrough/deleted
                    ...droppedCols.map((col) {
                      final name = col['field_name'];

                      return TableRow(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          border: const Border(bottom: BorderSide(color: Color(0xFF334155))),
                        ),
                        children: [
                          _buildDeletedCell(col['comment'] ?? ''),
                          _buildDeletedCell(name, isBold: true),
                          _buildDeletedCell(col['data_type']),
                          _buildDeletedCell(col['data_size']?.toString() ?? '-'),
                          _buildDeletedCell(col['decimal_places']?.toString() ?? '-'),
                          _buildDeletedCell(col['is_pk'] == true ? 'PK' : '-'),
                          _buildDeletedCell(col['is_ai'] == true ? 'AI' : '-'),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextButton(
                                onPressed: () {
                                  // Restore deleted column by removing drop_column change
                                  setState(() {
                                    state.stagedChanges.removeWhere(
                                        (c) => c['action'] == 'drop_column' && c['field_name'] == name);
                                  });
                                  state.clearErrorMessage(); // Refresh trigger
                                },
                                child: const Text('실행 취소(Undo)', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildTextCell(BuildContext context, String text, {bool isNew = false, bool isModified = false, bool isBold = false}) {
    final state = AppStateProvider.of(context);
    final highlight = state.searchQuery;

    Color textColor = Colors.white;
    String badge = '';
    if (isNew) {
      textColor = Colors.greenAccent;
      badge = ' [신규]';
    } else if (isModified) {
      textColor = Colors.amberAccent;
      badge = ' *';
    }

    if (highlight.isNotEmpty) {
      final textLower = text.toLowerCase();
      final highlightLower = highlight.toLowerCase();
      
      if (textLower.contains(highlightLower)) {
        final List<InlineSpan> spans = [];
        int start = 0;
        int index = textLower.indexOf(highlightLower, start);
        
        while (index != -1) {
          if (index > start) {
            spans.add(TextSpan(text: text.substring(start, index), style: TextStyle(color: textColor)));
          }
          spans.add(TextSpan(
            text: text.substring(index, index + highlight.length),
            style: const TextStyle(
              color: Color(0xFF38BDF8), // Bright blue highlight!
              fontWeight: FontWeight.bold,
            ),
          ));
          start = index + highlight.length;
          index = textLower.indexOf(highlightLower, start);
        }
        
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: textColor)));
        }

        if (badge.isNotEmpty) {
          spans.add(TextSpan(
            text: badge,
            style: TextStyle(
              color: isNew ? Colors.green : Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ));
        }

        return TableCell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
                children: spans,
              ),
            ),
          ),
        );
      }
    }

    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: RichText(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
            children: [
              if (badge.isNotEmpty)
                TextSpan(
                  text: badge,
                  style: TextStyle(
                    color: isNew ? Colors.green : Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCell(String comment, {bool isNew = false, bool isModified = false}) {
    Color textColor = const Color(0xFF94A3B8);
    if (isNew) {
      textColor = Colors.greenAccent.withOpacity(0.8);
    } else if (isModified) {
      textColor = Colors.amberAccent.withOpacity(0.8);
    }

    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          comment.isEmpty ? '-' : comment,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontStyle: comment.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildDeletedCell(String text, {bool isBold = false}) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.redAccent.withOpacity(0.5),
            fontSize: 13,
            decoration: TextDecoration.lineThrough,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBooleanCell(bool val) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Icon(
          val ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
          size: 16,
          color: val ? const Color(0xFF6366F1) : const Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildActionsCell(BuildContext context, AppState state, Map<String, dynamic> col, bool isNew) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF60A5FA)),
              tooltip: '컬럼 수정',
              onPressed: () => _showColumnDialog(context, state, existingColumn: col),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              tooltip: '컬럼 삭제',
              onPressed: () => state.deleteColumn(col['field_name']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTableButton(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton.icon(
        onPressed: () => _showCreateTableDialog(context, state),
        icon: const Icon(Icons.create_new_folder_outlined, size: 16),
        label: const Text('테이블 생성'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  void _showColumnDialog(BuildContext context, AppState state, {Map<String, dynamic>? existingColumn}) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: existingColumn?['field_name'] ?? '');
    final sizeController = TextEditingController(text: existingColumn?['data_size']?.toString() ?? '');
    final scaleController = TextEditingController(text: existingColumn?['decimal_places']?.toString() ?? '');
    final commentController = TextEditingController(text: existingColumn?['comment'] ?? '');

    String selectedType = existingColumn?['data_type'] ?? 'varchar';
    bool isPk = existingColumn?['is_pk'] == true;
    bool isAi = existingColumn?['is_ai'] == true;

    final mysqlTypes = [
      'int', 'varchar', 'char', 'text', 'decimal', 'double', 'float',
      'datetime', 'date', 'timestamp', 'tinyint', 'bigint', 'blob'
    ];

    if (!mysqlTypes.contains(selectedType)) {
      mysqlTypes.add(selectedType);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                existingColumn == null ? '컬럼 추가' : '컬럼 수정',
                style: const TextStyle(color: Colors.white),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Field Name
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '필드명(Field Name)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        ),
                        validator: (v) => v!.isEmpty ? '필드명을 입력해주세요' : null,
                      ),
                      const SizedBox(height: 12),

                      // Data Type
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '데이터 타입(Data Type)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                        items: mysqlTypes.map((t) {
                          return DropdownMenuItem(value: t, child: Text(t));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Size & Decimal Scale
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: sizeController,
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '크기/길이(Size)',
                                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: scaleController,
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '소수점 이하 자리수(Scale)',
                                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Primary Key & Auto Increment Switch Checkboxes
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('기본키 (PK)', style: TextStyle(color: Colors.white, fontSize: 13)),
                              value: isPk,
                              activeColor: const Color(0xFF6366F1),
                              onChanged: (v) {
                                setDialogState(() {
                                  isPk = v ?? false;
                                  if (!isPk) {
                                    isAi = false; // Auto increment requires PK
                                  }
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('자동증가 (AI)', style: TextStyle(color: Colors.white, fontSize: 13)),
                              value: isAi,
                              activeColor: const Color(0xFF6366F1),
                              onChanged: isPk
                                  ? (v) {
                                      setDialogState(() {
                                        isAi = v ?? false;
                                      });
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),

                      // Column Comment
                      TextFormField(
                        controller: commentController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '설명(Comment)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    
                    final colMap = {
                      'field_name': nameController.text.trim(),
                      'data_type': selectedType,
                      'data_size': sizeController.text.isEmpty ? null : int.tryParse(sizeController.text),
                      'decimal_places': scaleController.text.isEmpty ? null : int.tryParse(scaleController.text),
                      'is_pk': isPk,
                      'is_ai': isAi,
                      'comment': commentController.text.trim(),
                    };

                    if (existingColumn == null) {
                      state.addColumn(colMap);
                    } else {
                      state.modifyColumn(existingColumn['field_name'], colMap);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('컬럼 임시저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateTableDialog(BuildContext context, AppState state) {
    final formKey = GlobalKey<FormState>();
    final tableController = TextEditingController();

    // Default first column
    final fieldController = TextEditingController(text: 'id');
    String colType = 'int';
    bool isPk = true;
    bool isAi = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('테이블 생성', style: TextStyle(color: Colors.white)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: tableController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '테이블명(Table Name)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        ),
                        validator: (v) => v!.isEmpty ? '테이블명을 입력해주세요' : null,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '초기 설정 컬럼(INITIAL COLUMN)',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: fieldController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '컬럼명(Column Name)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                        validator: (v) => v!.isEmpty ? '컬럼명을 입력해주세요' : null,
                      ),
                      DropdownButtonFormField<String>(
                        value: colType,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: '타입(Type)'),
                        items: const [
                          DropdownMenuItem(value: 'int', child: Text('int')),
                          DropdownMenuItem(value: 'varchar', child: Text('varchar')),
                          DropdownMenuItem(value: 'bigint', child: Text('bigint')),
                          DropdownMenuItem(value: 'text', child: Text('text')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              colType = val;
                            });
                          }
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('PK', style: TextStyle(color: Colors.white, fontSize: 13)),
                              value: isPk,
                              onChanged: (v) {
                                setDialogState(() {
                                  isPk = v ?? false;
                                  if (!isPk) isAi = false;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('자동증가', style: TextStyle(color: Colors.white, fontSize: 13)),
                              value: isAi,
                              onChanged: isPk ? (v) {
                                setDialogState(() {
                                  isAi = v ?? false;
                                });
                              } : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    
                    final colMap = {
                      'field_name': fieldController.text.trim(),
                      'data_type': colType,
                      'data_size': colType == 'varchar' ? 255 : null,
                      'decimal_places': null,
                      'is_pk': isPk,
                      'is_ai': isAi,
                      'comment': 'Initial column',
                    };

                    state.stageTableCreation(tableController.text.trim(), [colMap]);
                    Navigator.of(context).pop();
                    
                    // Show a snackbar telling user change is staged
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('테이블 "${tableController.text.trim()}" 생성이 임시 저장되었습니다. 아래 "변경 저장"을 클릭하여 실행하세요.'),
                        backgroundColor: const Color(0xFF1E1B4B),
                      )
                    );
                  },
                  child: const Text('테이블 생성 대기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleTableManagement(BuildContext context, AppState state, String action) {
    if (action == 'create_table') {
      _showCreateTableDialog(context, state);
    } else if (action == 'drop_table') {
      if (state.selectedTable == null) return;
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text('테이블 삭제 대기: ${state.selectedTable}?', style: const TextStyle(color: Colors.white)),
            content: const Text(
              '선택한 테이블의 삭제를 임시 저장합니다. 아래 "변경 저장"을 클릭하기 전에는 실행되지 않습니다.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                onPressed: () {
                  state.stageTableDrop(state.selectedTable!);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('삭제 대기'),
              ),
            ],
          );
        },
      );
    } else if (action == 'create_index') {
      _showCreateIndexDialog(context, state);
    }
  }

  void _showCreateIndexDialog(BuildContext context, AppState state) {
    final formKey = GlobalKey<FormState>();
    final idxController = TextEditingController();
    bool isUnique = false;

    // Multi-select for index columns
    final List<String> selectedCols = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('인덱스 생성', style: TextStyle(color: Colors.white)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: idxController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '인덱스명(Index Name)',
                          labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                          hintText: 'idx_column_name',
                          hintStyle: TextStyle(color: Color(0xFF475569)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        ),
                        validator: (v) => v!.isEmpty ? '인덱스명을 입력해주세요' : null,
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('유니크 인덱스(Unique Index)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        value: isUnique,
                        activeColor: const Color(0xFF6366F1),
                        onChanged: (v) {
                          setDialogState(() {
                            isUnique = v ?? false;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '컬럼 선택(SELECT COLUMNS)',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      // List of column checkboxes
                      ...state.visibleColumns.map((col) {
                        final name = col['field_name'];
                        final isColChecked = selectedCols.contains(name);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          value: isColChecked,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedCols.add(name);
                              } else {
                                selectedCols.remove(name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedCols.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('인덱스를 생성할 컬럼을 최소 하나 이상 선택하세요.'))
                      );
                      return;
                    }

                    state.stageIndexCreation(state.selectedTable!, idxController.text.trim(), selectedCols, isUnique);
                    Navigator.of(context).pop();
                  },
                  child: const Text('인덱스 생성 대기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmSaveStagedChanges(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('임시 저장된 변경사항을 반영하시겠습니까?', style: TextStyle(color: Colors.white)),
          content: Text(
            '이 ${state.stagedChanges.length}개의 변경사항을 데이터베이스에 반영하시겠습니까? 이 DDL 작업은 테이블 스키마 구조를 변경합니다.',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                state.saveTableChanges();
              },
              child: const Text('변경 반영'),
            ),
          ],
        );
      },
    );
  }

  void _handleAutoGeneration(BuildContext context, AppState state, String option) {
    final tableName = state.selectedTable!;
    final columns = state.visibleColumns;

    String generatedCode = '';
    String title = '';

    switch (option) {
      case 'sql_create_table':
        generatedCode = CodeGenerator.generateCreateTable(tableName, columns);
        title = 'CREATE TABLE Script';
        break;
      case 'sql_alter_add':
        generatedCode = CodeGenerator.generateAlterTableAdd(tableName, columns);
        title = 'ALTER TABLE ADD Script';
        break;
      case 'sql_drop_table':
        generatedCode = CodeGenerator.generateDropTable(tableName);
        title = 'DROP TABLE Script';
        break;
      case 'sql_insert':
        generatedCode = CodeGenerator.generateInsertInto(tableName, columns);
        title = 'INSERT INTO Script Template';
        break;
      case 'sql_update':
        generatedCode = CodeGenerator.generateUpdateSet(tableName, columns);
        title = 'UPDATE SET Script Template';
        break;
      case 'sql_upsert':
        generatedCode = CodeGenerator.generateUpsert(tableName, columns);
        title = 'UPSERT Script Template';
        break;
      case 'obj_flutter':
        generatedCode = CodeGenerator.generateFlutterObject(tableName, columns);
        title = 'Flutter/Dart Class';
        break;
      case 'obj_go':
        generatedCode = CodeGenerator.generateGoObject(tableName, columns);
        title = 'Go Struct';
        break;
      case 'obj_python':
        generatedCode = CodeGenerator.generatePythonObject(tableName, columns);
        title = 'Python Class';
        break;
      case 'obj_delphi':
        generatedCode = CodeGenerator.generateDelphiObject(tableName, columns);
        title = 'Delphi Object/Class';
        break;
    }

    // Show popup
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Color(0xFF38BDF8), size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: generatedCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('클립보드에 복사되었습니다!'), duration: Duration(seconds: 1)),
                  );
                },
                tooltip: '클립보드 복사',
              )
            ],
          ),
          content: Container(
            width: 600,
            height: 380,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                generatedCode,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        );
      },
    );
  }
}
