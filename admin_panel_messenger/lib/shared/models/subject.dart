class Subject {
  final int id;
  final String name;
  final int assignmentCount;

  const Subject({
    required this.id,
    required this.name,
    required this.assignmentCount,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        assignmentCount: json['assignmentCount'] as int? ?? 0,
      );
}

class TeacherAssignment {
  final int id;
  final int subjectId;
  final String subjectName;
  final String groupName;

  const TeacherAssignment({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.groupName,
  });

  factory TeacherAssignment.fromJson(Map<String, dynamic> json) =>
      TeacherAssignment(
        id: json['id'] as int,
        subjectId: json['subjectId'] as int? ?? 0,
        subjectName: json['subjectName'] as String? ?? '',
        groupName: json['groupName'] as String? ?? '',
      );
}
