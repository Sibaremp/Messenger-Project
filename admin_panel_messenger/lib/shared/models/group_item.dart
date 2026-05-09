class GroupItem {
  final String name;
  final int peopleCount;
  final int userCount;

  const GroupItem({
    required this.name,
    required this.peopleCount,
    required this.userCount,
  });

  factory GroupItem.fromJson(Map<String, dynamic> json) => GroupItem(
        name: json['name'] as String? ?? '',
        peopleCount: json['peopleCount'] as int? ?? 0,
        userCount: json['userCount'] as int? ?? 0,
      );
}
