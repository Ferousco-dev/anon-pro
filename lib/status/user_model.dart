class User {
  final String id;
  final String username;
  final String avatarUrl;

  const User({
    required this.id,
    required this.username,
    required this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['display_name'] ?? json['alias'] as String,
      avatarUrl: json['profile_image_url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': username,
      'profile_image_url': avatarUrl,
    };
  }
}
