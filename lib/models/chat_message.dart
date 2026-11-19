class ChatMessage {
  final String id;
  final String region;
  final String? userId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.region,
    this.userId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      region: (json['region'] ?? 'Общий чат').toString(),
      userId: json['user_id']?.toString(),
      authorName: (json['author_name'] ?? 'Рыбак').toString(),
      text: (json['message_text'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
