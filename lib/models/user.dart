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

  bool get isEmpty => telegram == null && vk == null && github == null && website == null;
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
  final SocialLinks? socialLinks;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.status,
    this.isOnline = false,
    this.socialLinks,
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
    socialLinks: json['socialLinks'] != null
        ? SocialLinks.fromJson(json['socialLinks'] as Map<String, dynamic>)
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
    if (socialLinks != null) 'socialLinks': socialLinks!.toJson(),
  };
}
