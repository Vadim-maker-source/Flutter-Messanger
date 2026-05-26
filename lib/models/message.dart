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

  // Поля для пересланных сообщений (заполняются API-ом forward).
  final String? forwardedFromMessageId;
  final String? forwardedFromChatId;
  final String? forwardedFromChatName;
  final String? forwardedFromChatType;
  final String? forwardedFromUserId;
  final String? forwardedFromUserName;

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
    this.forwardedFromMessageId,
    this.forwardedFromChatId,
    this.forwardedFromChatName,
    this.forwardedFromChatType,
    this.forwardedFromUserId,
    this.forwardedFromUserName,
  });

  bool get isForwarded =>
      forwardedFromChatName != null || forwardedFromUserName != null;

  /// Возвращает копию с переопределёнными полями. Полезно при обновлении
  /// сообщения (новые reactions / readReceipts / редактирование) — все поля
  /// о пересылке и пр. сохраняются автоматически.
  Message copyWith({
    String? id,
    String? content,
    String? fileUrl,
    String? fileName,
    String? fileType,
    String? userId,
    User? user,
    String? chatId,
    String? replyToId,
    Message? replyTo,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
    List<ReadReceipt>? readReceipts,
    Map<String, dynamic>? reactions,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      userId: userId ?? this.userId,
      user: user ?? this.user,
      chatId: chatId ?? this.chatId,
      replyToId: replyToId ?? this.replyToId,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      readReceipts: readReceipts ?? this.readReceipts,
      reactions: reactions ?? this.reactions,
      forwardedFromMessageId: forwardedFromMessageId,
      forwardedFromChatId: forwardedFromChatId,
      forwardedFromChatName: forwardedFromChatName,
      forwardedFromChatType: forwardedFromChatType,
      forwardedFromUserId: forwardedFromUserId,
      forwardedFromUserName: forwardedFromUserName,
    );
  }

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
    forwardedFromMessageId: json['forwardedFromMessageId'] as String?,
    forwardedFromChatId: json['forwardedFromChatId'] as String?,
    forwardedFromChatName: json['forwardedFromChatName'] as String?,
    forwardedFromChatType: json['forwardedFromChatType'] as String?,
    forwardedFromUserId: json['forwardedFromUserId'] as String?,
    forwardedFromUserName: json['forwardedFromUserName'] as String?,
  );

  bool isReadBy(String userId) => readReceipts.any((r) => r.userId == userId);
}
