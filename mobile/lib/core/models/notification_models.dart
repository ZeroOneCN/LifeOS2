/// 通知中心模型（`GET /notifications` 列表项）。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.content,
    required this.category,
    this.source,
    required this.read,
    required this.notifyDate,
    this.note,
  });

  final int id;
  final String title;
  final String? content;
  final String category;
  final String? source;
  final bool read;
  final String notifyDate;
  final String? note;

  /// 正文转一行摘要：去掉换行与多余空白，供折叠态两行截断展示。
  String get summary {
    return (content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 标记已读后的本地副本（其他字段保持不变）。
  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      title: title,
      content: content,
      category: category,
      source: source,
      read: read ?? this.read,
      notifyDate: notifyDate,
      note: note,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      content: json['content'] as String?,
      category: json['category'] as String? ?? '',
      source: json['source'] as String?,
      read: json['read'] as bool? ?? false,
      notifyDate: json['notify_date'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}
