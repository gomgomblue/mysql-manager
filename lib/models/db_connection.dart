class DbConnection {
  final String host;
  final int port;
  final String user;
  final String password;
  final String? database;
  final String? label;
  final DateTime? lastUsed;

  DbConnection({
    required this.host,
    this.port = 3306,
    required this.user,
    required this.password,
    this.database,
    this.label,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'user': user,
      'password': password,
      'database': database,
      'label': label,
      'lastUsed': lastUsed?.toIso8601String(),
    };
  }

  factory DbConnection.fromJson(Map<String, dynamic> json) {
    return DbConnection(
      host: json['host'] ?? '',
      port: json['port'] ?? 3306,
      user: json['user'] ?? '',
      password: json['password'] ?? '',
      database: json['database'],
      label: json['label'],
      lastUsed: json['lastUsed'] != null ? DateTime.tryParse(json['lastUsed']) : null,
    );
  }

  String get displayName {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    String dbStr = (database != null && database!.isNotEmpty) ? '/$database' : '';
    return '$user@$host:$port$dbStr';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbConnection &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          user == other.user &&
          password == other.password &&
          database == other.database;

  @override
  int get hashCode =>
      host.hashCode ^ port.hashCode ^ user.hashCode ^ password.hashCode ^ database.hashCode;
}
