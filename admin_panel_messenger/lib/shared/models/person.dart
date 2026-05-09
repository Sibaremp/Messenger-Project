class Person {
  final int id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String role;
  final String? group;
  final bool hasUser;

  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.role,
    this.group,
    required this.hasUser,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id:         json['id'] as int,
      firstName:  json['firstName'] as String,
      lastName:   json['lastName'] as String,
      middleName: json['middleName'] as String?,
      role:       json['role'] as String,
      group:      json['group'] as String?,
      hasUser:    json['hasUser'] as bool,
    );
  }

  Person copyWith({
    String? firstName,
    String? lastName,
    String? middleName,
    String? role,
    String? group,
  }) {
    return Person(
      id:         id,
      firstName:  firstName  ?? this.firstName,
      lastName:   lastName   ?? this.lastName,
      middleName: middleName ?? this.middleName,
      role:       role       ?? this.role,
      group:      group      ?? this.group,
      hasUser:    hasUser,
    );
  }

  String get fullName {
    final parts = [lastName, firstName];
    if (middleName != null && middleName!.isNotEmpty) parts.add(middleName!);
    return parts.join(' ');
  }

  String get roleDisplay =>
      role.toLowerCase() == 'teacher' ? 'Преподаватель' : 'Студент';
}
