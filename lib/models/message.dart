import 'user.dart';

class ReadReceipt {
  final String userId;
  final DateTime readAt;
  final User? user;

  ReadReceipt({required this.userId, required this.readAt, this.user});

  factory ReadReceipt.fromJson(Map<String, dynamic> json) => ReadReceipt(
    userId: json['userId'],
    readAt: DateTime.parse(json['readAt']),
    user: json['user'] != null ? User.fromJson(json['user']) : null,
  );
}

class Message {
  final String id;
  final String content;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String userId;
  final User? user;
  final String chatId;
  final String? replyToId;
  final Message? replyTo;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool deleted;
  final List<ReadReceipt> readReceipts;
  final Map<String, dynamic>? reactions;

  Message({
    required this.id,
    required this.content,
    this.fileUrl,
    this.fileName,
    this.fileType,
    required this.userId,
    this.user,
    required this.chatId,
    this.replyToId,
    this.replyTo,
    required this.createdAt,
    this.updatedAt,
    this.deleted = false,
    this.readReceipts = const [],
    this.reactions,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    content: json['content'] ?? '',
    fileUrl: json['fileUrl'],
    fileName: json['fileName'],
    fileType: json['fileType'],
    userId: json['userId'],
    user: json['user'] != null ? User.fromJson(json['user']) : null,
    chatId: json['chatId'],
    replyToId: json['replyToId'],
    replyTo: json['replyTo'] != null ? Message.fromJson(json['replyTo']) : null,
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    deleted: json['deleted'] ?? false,
    readReceipts: (json['readReceipts'] as List? ?? [])
        .map((r) => ReadReceipt.fromJson(r))
        .toList(),
    reactions: json['reactions'] as Map<String, dynamic>?,
  );

  bool isReadBy(String userId) => readReceipts.any((r) => r.userId == userId);
}
