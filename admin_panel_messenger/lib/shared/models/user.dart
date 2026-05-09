class User {
  final int id;
  final String login;
  final String role;
  final String? group;
  final String? phone;
  final String? lastName;
  final String? firstName;
  final String? middleName;

  const User({
    required this.id,
    required this.login,
    required this.role,
    this.group,
    this.phone,
    this.lastName,
    this.firstName,
    this.middleName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id:         json['id'] as int,
      login:      json['login'] as String,
      role:       json['role'] as String? ?? 'student',
      group:      json['group'] as String?,
      phone:      json['phone'] as String?,
      lastName:   json['lastName'] as String?,
      firstName:  json['firstName'] as String?,
      middleName: json['middleName'] as String?,
    );
  }

  User copyWith({
    String? login,
    String? role,
    String? group,
    String? phone,
  }) {
    return User(
      id:         id,
      login:      login ?? this.login,
      role:       role  ?? this.role,
      group:      group ?? this.group,
      phone:      phone ?? this.phone,
      lastName:   lastName,
      firstName:  firstName,
      middleName: middleName,
    );
  }

  /// Фамилия + инициалы, если есть в ответе бэкенда.
  /// Иначе — сам логин.
  String get displayName {
    if (lastName != null && lastName!.isNotEmpty) {
      final parts = <String>[lastName!];
      if (firstName != null && firstName!.isNotEmpty) {
        parts.add('${firstName![0]}.');
        if (middleName != null && middleName!.isNotEmpty) {
          parts.add('${middleName![0]}.');
        }
      }
      return parts.join(' ');
    }
    return login;
  }

  /// Первая буква для аватара.
  String get avatarLetter {
    if (lastName != null && lastName!.isNotEmpty) return lastName![0].toUpperCase();
    return login.isNotEmpty ? login[0].toUpperCase() : '?';
  }

  String get roleDisplay =>
      role.toLowerCase() == 'teacher' ? 'Преподаватель' : 'Студент';
}
