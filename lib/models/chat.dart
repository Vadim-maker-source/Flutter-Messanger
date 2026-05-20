class Chat {
  final String id;
  final String title;
  final String? imageUrl;
  final String? lastMessage;
  final String type;
  final int unreadCount;
  final String? role; // CREATOR, ADMIN, MEMBER

  Chat({
    required this.id,
    required this.title,
    this.imageUrl,
    this.lastMessage,
    required this.type,
    this.unreadCount = 0,
    this.role,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      title: json['title'],
      imageUrl: json['imageUrl'],
      lastMessage: json['lastMessage'],
      type: json['type'] ?? 'PRIVATE',
      role: json['role'],
    );
  }

  /// Minimal stub used when navigating from a notification (only id is known).
  factory Chat.stub(String id) => Chat(id: id, title: '', type: 'PRIVATE');

  factory Chat.fromSidebar(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      title: json['title'] ?? 'Чат',
      imageUrl: json['image'],
      lastMessage: json['lastMessage']?['content'],
      type: json['type'] ?? 'PRIVATE',
      unreadCount: json['unreadCount'] ?? 0,
      role: json['role'],
    );
  }
}
