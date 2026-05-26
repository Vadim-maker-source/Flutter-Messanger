class SocialLinks {
  final String? telegram;
  final String? vk;
  final String? github;
  final String? website;

  const SocialLinks({this.telegram, this.vk, this.github, this.website});

  factory SocialLinks.fromJson(Map<String, dynamic> json) => SocialLinks(
    telegram: json['telegram'],
    vk: json['vk'],
    github: json['github'],
    website: json['website'],
  );

  Map<String, dynamic> toJson() => {
    if (telegram != null) 'telegram': telegram,
    if (vk != null) 'vk': vk,
    if (github != null) 'github': github,
    if (website != null) 'website': website,
  };

  bool get isEmpty => (telegram?.isEmpty ?? true) &&
      (vk?.isEmpty ?? true) &&
      (github?.isEmpty ?? true) &&
      (website?.isEmpty ?? true);
}

class UserStats {
  final int messagesCount;
  final int chatsCount;
  const UserStats({this.messagesCount = 0, this.chatsCount = 0});

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        messagesCount: (json['messagesCount'] as num?)?.toInt() ?? 0,
        chatsCount: (json['chatsCount'] as num?)?.toInt() ?? 0,
      );
}

class User {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? status;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final SocialLinks? socialLinks;
  final UserStats? stats;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.status,
    this.isOnline = false,
    this.lastSeen,
    this.createdAt,
    this.socialLinks,
    this.stats,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    email: json['email'] ?? '',
    username: json['username'] ?? '',
    displayName: json['displayName'] ?? '',
    avatarUrl: json['avatarUrl'],
    bio: json['bio'],
    status: json['status'],
    isOnline: json['isOnline'] ?? false,
    lastSeen: json['lastSeen'] != null
        ? DateTime.tryParse(json['lastSeen'].toString())
        : null,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'].toString())
        : null,
    socialLinks: json['socialLinks'] != null
        ? SocialLinks.fromJson(
            Map<String, dynamic>.from(json['socialLinks'] as Map))
        : null,
    stats: json['stats'] != null
        ? UserStats.fromJson(Map<String, dynamic>.from(json['stats'] as Map))
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'status': status,
    'isOnline': isOnline,
    if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (socialLinks != null) 'socialLinks': socialLinks!.toJson(),
  };
}
