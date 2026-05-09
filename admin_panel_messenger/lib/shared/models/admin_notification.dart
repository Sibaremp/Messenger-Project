class AdminNotification {
  final int id;
  final String title;
  final String body;
  final String target;
  final DateTime createdAt;

  const AdminNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.createdAt,
  });

  factory AdminNotification.fromJson(Map<String, dynamic> json) =>
      AdminNotification(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        target: json['target'] as String? ?? 'all',
        createdAt: DateTime.tryParse(
                json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  String get targetDisplay {
    switch (target.toLowerCase()) {
      case 'all':
        return 'Все';
      case 'students':
        return 'Студенты';
      case 'teachers':
        return 'Преподаватели';
      default:
        return target;
    }
  }

  String get formattedDate {
    final d = createdAt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}.${pad(d.month)}.${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }
}
