import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../services/app_state_provider.dart';

const List<String> sqlKeywords = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'UPDATE', 'SET', 'DELETE',
  'CREATE', 'TABLE', 'DROP', 'ALTER', 'ADD', 'COLUMN', 'JOIN', 'LEFT', 'RIGHT',
  'INNER', 'ON', 'GROUP', 'BY', 'ORDER', 'LIMIT', 'AND', 'OR', 'NOT', 'IN',
  'LIKE', 'IS', 'NULL', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'DATABASE', 'INDEX',
  'VARCHAR', 'INT', 'TEXT', 'DATETIME', 'PRIMARY', 'KEY', 'AUTO_INCREMENT'
];

class SqlAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final int maxLines;
  final TextStyle? style;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;

  const SqlAutocompleteField({
    Key? key,
    required this.controller,
    required this.maxLines,
    this.style,
    required this.decoration,
    this.onChanged,
  }) : super(key: key);

  @override
  State<SqlAutocompleteField> createState() => _SqlAutocompleteFieldState();
}

class _SqlAutocompleteFieldState extends State<SqlAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _filteredSuggestions = [];
  String _currentWord = '';
  int _wordStartOffset = 0;
  int _selectedIndex = 0;
  StateSetter? _setStateOverlay;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (FocusNode node, KeyEvent event) {
      if (event is KeyDownEvent) {
        final key = event.logicalKey;
        if (_overlayEntry != null && _filteredSuggestions.isNotEmpty) {
          if (key == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _selectedIndex = (_selectedIndex + 1) % _filteredSuggestions.length;
            });
            _updateOverlay();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowUp) {
            setState(() {
              _selectedIndex = (_selectedIndex - 1 + _filteredSuggestions.length) % _filteredSuggestions.length;
            });
            _updateOverlay();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.enter) {
            if (_selectedIndex >= 0 && _selectedIndex < _filteredSuggestions.length) {
              _selectSuggestion(_filteredSuggestions[_selectedIndex]);
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.escape) {
            _hideOverlay();
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    };
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Small delay to allow tapping suggestion
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          _hideOverlay();
        }
      });
    }
  }

  void _updateOverlay() {
    _setStateOverlay?.call(() {});
  }

  void _onTextChanged() {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
      return;
    }

    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _hideOverlay();
      return;
    }

    final cursor = selection.baseOffset;
    if (cursor <= 0) {
      _hideOverlay();
      return;
    }

    // Find the start of the word being typed
    int start = cursor - 1;
    while (start >= 0) {
      final char = text[start];
      if (RegExp(r'[a-zA-Z0-9_\.]').hasMatch(char)) {
        start--;
      } else {
        break;
      }
    }
    _wordStartOffset = start + 1;
    _currentWord = text.substring(_wordStartOffset, cursor);

    if (_currentWord.isEmpty) {
      _hideOverlay();
      return;
    }

    final state = AppStateProvider.of(context);
    final Set<String> allSuggestions = {};

    // 1. SQL Keywords
    allSuggestions.addAll(sqlKeywords);
    // 2. Databases
    allSuggestions.addAll(state.databases);
    // 3. Tables
    if (state.selectedDatabase != null) {
      allSuggestions.addAll(state.tables[state.selectedDatabase] ?? []);
    }
    // 4. Columns
    for (final col in state.tableColumns) {
      if (col['field_name'] != null) {
        allSuggestions.add(col['field_name'] as String);
      }
    }

    final query = _currentWord.toLowerCase();
    final newFiltered = allSuggestions
        .where((s) => s.toLowerCase().startsWith(query) && s.toLowerCase() != query)
        .toList();

    newFiltered.sort((a, b) {
      final aStarts = a.toLowerCase().startsWith(query);
      final bStarts = b.toLowerCase().startsWith(query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return a.length.compareTo(b.length);
    });

    if (_filteredSuggestions.length != newFiltered.length ||
        _filteredSuggestions.isEmpty ||
        _filteredSuggestions.first != newFiltered.first) {
      _selectedIndex = 0;
    }

    _filteredSuggestions = newFiltered;

    if (_filteredSuggestions.length > 8) {
      _filteredSuggestions = _filteredSuggestions.sublist(0, 8);
    }

    if (_filteredSuggestions.isNotEmpty) {
      _showOverlay();
      _updateOverlay();
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry?.markNeedsBuild();
    }
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _setStateOverlay = null;
  }

  Offset _getCaretOffset() {
    try {
      final text = widget.controller.text;
      final selection = widget.controller.selection;
      if (!selection.isValid) return Offset.zero;

      final textUpToWord = text.substring(0, _wordStartOffset);

      final textPainter = TextPainter(
        text: TextSpan(
          text: textUpToWord,
          style: widget.style ?? const TextStyle(
            fontFamily: 'Courier',
            color: Color(0xFFE2E8F0),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      RenderBox renderBox = context.findRenderObject() as RenderBox;
      double inputWidth = renderBox.size.width;

      // Layout width accounting for left/right padding
      textPainter.layout(maxWidth: inputWidth - 32);

      final caretOffset = textPainter.getOffsetForCaret(
        TextPosition(offset: textUpToWord.length),
        Rect.zero,
      );

      // position below the current cursor text line
      double dy = caretOffset.dy + 16 + textPainter.preferredLineHeight;
      double dx = caretOffset.dx + 16;

      // Adjust horizontally to prevent card overflow
      if (dx + 280 > inputWidth) {
        dx = inputWidth - 290;
      }
      if (dx < 16) dx = 16;

      return Offset(dx, dy);
    } catch (e) {
      return const Offset(16, 40);
    }
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            _setStateOverlay = setStateOverlay;
            return Positioned(
              width: 280,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: _getCaretOffset(),
                child: Material(
                  elevation: 12,
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF475569), width: 1.5),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _filteredSuggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _filteredSuggestions[index];
                        final isSelected = index == _selectedIndex;
                        return InkWell(
                          onTap: () => _selectSuggestion(suggestion),
                          onHover: (hovering) {
                            if (hovering) {
                              setState(() {
                                _selectedIndex = index;
                              });
                              _updateOverlay();
                            }
                          },
                          hoverColor: Colors.transparent,
                          splashColor: const Color(0xFF475569).withOpacity(0.3),
                          highlightColor: Colors.transparent,
                          child: Container(
                            color: isSelected ? const Color(0xFF334155) : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  _getSuggestionIcon(suggestion),
                                  size: 14,
                                  color: _getSuggestionColor(suggestion),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    suggestion,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getSuggestionIcon(String val) {
    final state = AppStateProvider.of(context);
    if (sqlKeywords.contains(val)) return Icons.code;
    if (state.databases.contains(val)) return Icons.storage;
    if (state.selectedDatabase != null &&
        (state.tables[state.selectedDatabase] ?? []).contains(val)) {
      return Icons.table_chart;
    }
    return Icons.view_column;
  }

  Color _getSuggestionColor(String val) {
    final state = AppStateProvider.of(context);
    if (sqlKeywords.contains(val)) return const Color(0xFF38BDF8); // keyword blue
    if (state.databases.contains(val)) return Colors.amber; // db amber
    if (state.selectedDatabase != null &&
        (state.tables[state.selectedDatabase] ?? []).contains(val)) {
      return const Color(0xFF818CF8); // table indigo
    }
    return Colors.greenAccent; // field green
  }

  void _selectSuggestion(String suggestion) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final cursor = selection.baseOffset;
    final newText = text.replaceRange(_wordStartOffset, cursor, suggestion);
    
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _wordStartOffset + suggestion.length,
      ),
    );

    if (widget.onChanged != null) {
      widget.onChanged!(newText);
    }

    // Return focus to TextField
    _focusNode.requestFocus();
    _hideOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: widget.maxLines,
        style: widget.style,
        decoration: widget.decoration,
        onChanged: widget.onChanged,
      ),
    );
  }
}
