import '../models/db_connection.dart';

class CodeGenerator {
  static String generateCreateTable(String tableName, List<Map<String, dynamic>> columns) {
    List<String> colDefs = [];
    List<String> pks = [];

    for (var col in columns) {
      final name = col['field_name'];
      final type = col['data_type'];
      final size = col['data_size'];
      final scale = col['decimal_places'];
      final isPk = col['is_pk'] == true;
      final isAi = col['is_ai'] == true;
      final comment = col['comment'] ?? '';

      String def = '  `$name` $type';
      if (size != null && size.toString().trim().isNotEmpty) {
        if (scale != null && scale.toString().trim().isNotEmpty) {
          def += '($size,$scale)';
        } else {
          def += '($size)';
        }
      }

      if (isAi) {
        def += ' AUTO_INCREMENT';
      }

      if (comment.isNotEmpty) {
        def += " COMMENT '${comment.replaceAll("'", "''")}'";
      }

      colDefs.add(def);

      if (isPk) {
        pks.add('`$name`');
      }
    }

    if (pks.isNotEmpty) {
      colDefs.add('  PRIMARY KEY (${pks.join(', ')})');
    }

    return 'CREATE TABLE `$tableName` (\n${colDefs.join(',\n')}\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
  }

  static String generateAlterTableAdd(String tableName, List<Map<String, dynamic>> columns) {
    List<String> statements = [];

    for (var col in columns) {
      final name = col['field_name'];
      final type = col['data_type'];
      final size = col['data_size'];
      final scale = col['decimal_places'];
      final isAi = col['is_ai'] == true;
      final comment = col['comment'] ?? '';

      String def = '`$name` $type';
      if (size != null && size.toString().trim().isNotEmpty) {
        if (scale != null && scale.toString().trim().isNotEmpty) {
          def += '($size,$scale)';
        } else {
          def += '($size)';
        }
      }

      if (isAi) {
        def += ' AUTO_INCREMENT';
      }

      if (comment.isNotEmpty) {
        def += " COMMENT '${comment.replaceAll("'", "''")}'";
      }

      statements.add('ALTER TABLE `$tableName` ADD COLUMN $def;');
    }

    return statements.join('\n');
  }

  static String generateDropTable(String tableName) {
    return 'DROP TABLE IF EXISTS `$tableName`;';
  }

  static String generateInsertInto(String tableName, List<Map<String, dynamic>> columns) {
    final nonAiCols = columns.where((c) => c['is_ai'] != true).map((c) => '`${c['field_name']}`').toList();
    final placeholders = columns.where((c) => c['is_ai'] != true).map((c) {
      final type = c['data_type'].toString().toLowerCase();
      if (type.contains('int') || type.contains('decimal') || type.contains('double') || type.contains('float')) {
        return '0';
      }
      return "'val'";
    }).toList();

    return 'INSERT INTO `$tableName` (${nonAiCols.join(', ')})\nVALUES (${placeholders.join(', ')});';
  }

  static String generateUpdateSet(String tableName, List<Map<String, dynamic>> columns) {
    final sets = columns.where((c) => c['is_pk'] != true && c['is_ai'] != true).map((c) {
      final name = c['field_name'];
      final type = c['data_type'].toString().toLowerCase();
      final val = (type.contains('int') || type.contains('decimal') || type.contains('double') || type.contains('float'))
          ? '0'
          : "'val'";
      return '  `$name` = $val';
    }).toList();

    final pks = columns.where((c) => c['is_pk'] == true).map((c) => '`${c['field_name']}` = 1').toList();
    final whereClause = pks.isNotEmpty ? pks.join(' AND ') : '1 = 1';

    return 'UPDATE `$tableName` SET\n${sets.join(',\n')}\nWHERE $whereClause;';
  }

  static String generateUpsert(String tableName, List<Map<String, dynamic>> columns) {
    final colNames = columns.map((c) => '`${c['field_name']}`').toList();
    final placeholders = columns.map((c) {
      final type = c['data_type'].toString().toLowerCase();
      if (type.contains('int') || type.contains('decimal') || type.contains('double') || type.contains('float')) {
        return '0';
      }
      return "'val'";
    }).toList();

    final updates = columns.where((c) => c['is_pk'] != true && c['is_ai'] != true).map((c) {
      final name = c['field_name'];
      return '`$name` = VALUES(`$name`)';
    }).toList();

    String sql = 'INSERT INTO `$tableName` (${colNames.join(', ')})\nVALUES (${placeholders.join(', ')})';
    if (updates.isNotEmpty) {
      sql += '\nON DUPLICATE KEY UPDATE\n  ${updates.join(',\n  ')};';
    } else {
      sql += ';';
    }
    return sql;
  }

  // Maps MySQL types to Dart types
  static String _getDartType(String dbType) {
    final type = dbType.toLowerCase();
    if (type.contains('int') || type.contains('bit')) return 'int';
    if (type.contains('decimal') || type.contains('double') || type.contains('float') || type.contains('numeric')) return 'double';
    if (type.contains('bool') || type.contains('boolean')) return 'bool';
    if (type.contains('date') || type.contains('time')) return 'DateTime';
    return 'String';
  }

  static String generateFlutterObject(String tableName, List<Map<String, dynamic>> columns) {
    final className = _toPascalCase(tableName);
    List<String> fields = [];
    List<String> params = [];
    List<String> fromJson = [];
    List<String> toJson = [];

    for (var col in columns) {
      final name = col['field_name'];
      final dartType = _getDartType(col['data_type']);
      final camelName = _toCamelCase(name);

      fields.add('  final $dartType $camelName;');
      params.add('    required this.$camelName,');

      if (dartType == 'DateTime') {
        fromJson.add("      $camelName: json['$name'] != null ? DateTime.parse(json['$name']) : DateTime.now(),");
        toJson.add("      '$name': $camelName.toIso8601String(),");
      } else if (dartType == 'double') {
        fromJson.add("      $camelName: (json['$name'] as num?)?.toDouble() ?? 0.0,");
        toJson.add("      '$name': $camelName,");
      } else if (dartType == 'int') {
        fromJson.add("      $camelName: json['$name'] as int? ?? 0,");
        toJson.add("      '$name': $camelName,");
      } else if (dartType == 'bool') {
        fromJson.add("      $camelName: json['$name'] as bool? ?? false,");
        toJson.add("      '$name': $camelName,");
      } else {
        fromJson.add("      $camelName: json['$name'] as String? ?? '',");
        toJson.add("      '$name': $camelName,");
      }
    }

    return '''class $className {
${fields.join('\n')}

  $className({
${params.join('\n')}
  });

  factory $className.fromJson(Map<String, dynamic> json) {
    return $className(
${fromJson.join('\n')}
    );
  }

  Map<String, dynamic> toJson() {
    return {
${toJson.join('\n')}
    };
  }
}''';
  }

  // Maps MySQL types to Go types
  static String _getGoType(String dbType) {
    final type = dbType.toLowerCase();
    if (type.contains('bigint')) return 'int64';
    if (type.contains('int')) return 'int';
    if (type.contains('decimal') || type.contains('double') || type.contains('float') || type.contains('numeric')) return 'float64';
    if (type.contains('bool') || type.contains('boolean')) return 'bool';
    if (type.contains('date') || type.contains('time')) return 'time.Time';
    return 'string';
  }

  static String generateGoObject(String tableName, List<Map<String, dynamic>> columns) {
    final structName = _toPascalCase(tableName);
    List<String> fields = [];

    for (var col in columns) {
      final name = col['field_name'];
      final goType = _getGoType(col['data_type']);
      final pascalName = _toPascalCase(name);
      fields.add('    $pascalName $goType `json:"$name" db:"$name"`');
    }

    return 'type $structName struct {\n${fields.join('\n')}\n}';
  }

  // Maps MySQL types to Python types
  static String _getPythonType(String dbType) {
    final type = dbType.toLowerCase();
    if (type.contains('int') || type.contains('bit')) return 'int';
    if (type.contains('decimal') || type.contains('double') || type.contains('float') || type.contains('numeric')) return 'float';
    if (type.contains('bool') || type.contains('boolean')) return 'bool';
    if (type.contains('date') || type.contains('time')) return 'datetime';
    return 'str';
  }

  static String generatePythonObject(String tableName, List<Map<String, dynamic>> columns) {
    final className = _toPascalCase(tableName);
    List<String> initArgs = ['self'];
    List<String> initBody = [];
    List<String> dictBody = [];

    for (var col in columns) {
      final name = col['field_name'];
      final pyType = _getPythonType(col['data_type']);
      final cleanName = _toSnakeCase(name);

      initArgs.add('$cleanName: $pyType');
      initBody.add('        self.$cleanName = $cleanName');
      dictBody.add("            '$name': self.$cleanName,");
    }

    return '''class $className:
    def __init__(${initArgs.join(', ')}):
${initBody.join('\n')}

    def to_dict(self):
        return {
${dictBody.join('\n')}
        }
''';
  }

  // Maps MySQL types to Delphi types
  static String _getDelphiType(String dbType) {
    final type = dbType.toLowerCase();
    if (type.contains('bigint')) return 'Int64';
    if (type.contains('int')) return 'Integer';
    if (type.contains('decimal') || type.contains('double') || type.contains('float') || type.contains('numeric')) return 'Double';
    if (type.contains('bool') || type.contains('boolean')) return 'Boolean';
    if (type.contains('date') || type.contains('time')) return 'TDateTime';
    return 'string';
  }

  static String generateDelphiObject(String tableName, List<Map<String, dynamic>> columns) {
    final className = 'T' + _toPascalCase(tableName);
    List<String> fields = [];
    List<String> properties = [];

    for (var col in columns) {
      final name = col['field_name'];
      final delphiType = _getDelphiType(col['data_type']);
      final pascalName = _toPascalCase(name);

      fields.add('    F$pascalName: $delphiType;');
      properties.add('    property $pascalName: $delphiType read F$pascalName write F$pascalName;');
    }

    return '''$className = class
  private
${fields.join('\n')}
  public
${properties.join('\n')}
  end;''';
  }

  // Utility casing functions
  static String _toPascalCase(String text) {
    return text.split(RegExp(r'[-_]')).map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join('');
  }

  static String _toCamelCase(String text) {
    final pascal = _toPascalCase(text);
    if (pascal.isEmpty) return '';
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

  static String _toSnakeCase(String text) {
    return text.replaceAllMapped(RegExp(r'([A-Z])'), (Match match) {
      return '_' + match.group(0)!.toLowerCase();
    }).replaceAll(RegExp(r'^_'), '').toLowerCase();
  }
}
