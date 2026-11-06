/// 报告域模型：财务 / 投资报告列表与明细。
///
/// 字段与网页端 `pages/finance/reports.tsx`、`pages/investment/reports.tsx` 对齐：
/// - 列表：`GET /finance/reports`、`GET /investment/reports`（返回数组）；
/// - 明细：`GET /finance/reports/{id}`、`GET /investment/reports/{id}`；
/// - 明细 `content` 为区块数组：`{"type":"h2","text":...}` 与
///   `{"type":"table","header":[...],"rows":[[...]]}`。
library;

int _toInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

String? _toText(Object? value) => value is String ? value : null;

/// 报告标题去重：去掉标题里已由副标题展示的统计区间，避免同一区间出现两次。
///
/// 与网页端 `reportTitle()` 规则一致：
/// - 「2026-08-07 ~ 2026-09-05 财务报告」→「财务报告」；
/// - 「健康报告（2026-08-07 至 2026-09-05）」→「健康报告」；
/// - 不含日期的括号（如行程名）保持原样。
String reportTitle(String? title) {
  if (title == null || title.isEmpty) {
    return '';
  }
  return title
      .replaceAll(
        RegExp(
          r'（\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}）',
        ),
        '',
      )
      .replaceFirst(
        RegExp(r'^\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2}\s+'),
        '',
      )
      .trim();
}

/// 报告摘要去重：剥离摘要开头的统计区间前缀（副标题已经展示区间）。
String reportSummaryText(String? summary) {
  if (summary == null || summary.isEmpty) {
    return '';
  }
  return summary
      .replaceFirst(
        RegExp(
          r'^统计区间\s*\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}\s*[，,、]?\s*',
        ),
        '',
      )
      .replaceFirst(
        RegExp(
          r'^\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}\s*[，,、]?\s*',
        ),
        '',
      )
      .trim();
}

/// 统计区间文案：起止齐全用「起 ~ 止」，否则退回后端 `period_label`。
String reportRange({
  String? start,
  String? end,
  String? label,
}) {
  if (start != null && end != null && start.isNotEmpty && end.isNotEmpty) {
    return '$start ~ $end';
  }
  return label ?? '';
}

/// ISO 时间 → `yyyy-MM-dd HH:mm`；纯日期原样返回；无效值返回空串。
String reportDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  bool isDateOnly = !value.contains('T');
  if (isDateOnly) {
    return value;
  }
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}

/// 报告列表项。
class ReportSummaryItem {
  const ReportSummaryItem({
    required this.id,
    required this.title,
    required this.periodLabel,
    this.createdAt,
  });

  final int id;
  final String title;
  final String periodLabel;
  final String? createdAt;

  /// 只含报告名的标题（区间交给副标题）。
  String get displayTitle => reportTitle(title);

  /// 副标题：统计区间。
  String get rangeText => periodLabel;

  /// 生成时间文案。
  String get createdText {
    final String text = reportDateTime(createdAt);
    return text.isEmpty ? '' : '生成于 $text';
  }

  factory ReportSummaryItem.fromJson(Map<String, dynamic> json) {
    return ReportSummaryItem(
      id: _toInt(json['id']),
      title: _toText(json['title']) ?? '',
      periodLabel: _toText(json['period_label']) ?? '',
      createdAt: _toText(json['created_at']),
    );
  }
}

/// 报告内容区块：标题（h2）或表格。
class ReportBlock {
  const ReportBlock({
    required this.type,
    this.text,
    this.header = const <String>[],
    this.rows = const <List<String>>[],
  });

  final String type;
  final String? text;
  final List<String> header;
  final List<List<String>> rows;

  bool get isHeading => type == 'h2';
  bool get isTable => type == 'table';

  factory ReportBlock.fromJson(Map<String, dynamic> json) {
    final Object? header = json['header'];
    final Object? rows = json['rows'];
    return ReportBlock(
      type: _toText(json['type']) ?? '',
      text: _toText(json['text']),
      header: header is List
          ? header.map((Object? v) => v?.toString() ?? '').toList()
          : const <String>[],
      rows: rows is List
          ? rows
              .whereType<List>()
              .map(
                (List row) => row
                    .map((Object? v) => v?.toString() ?? '')
                    .toList(),
              )
              .toList()
          : const <List<String>>[],
    );
  }
}

/// 报告明细。
class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.title,
    required this.periodLabel,
    this.periodStart,
    this.periodEnd,
    required this.summary,
    this.createdAt,
    required this.content,
  });

  final int id;
  final String title;
  final String periodLabel;
  final String? periodStart;
  final String? periodEnd;
  final String summary;
  final String? createdAt;
  final List<ReportBlock> content;

  /// 只含报告名的标题。
  String get displayTitle => reportTitle(title);

  /// 区间文案（只在副标题出现一次）。
  String get rangeText => reportRange(
        start: periodStart,
        end: periodEnd,
        label: periodLabel,
      );

  /// 去掉区间前缀后的摘要。
  String get displaySummary => reportSummaryText(summary);

  /// 生成时间文案。
  String get createdText {
    final String text = reportDateTime(createdAt);
    return text.isEmpty ? '' : '生成于 $text';
  }

  factory ReportDetail.fromJson(Map<String, dynamic> json) {
    final Object? content = json['content'];
    return ReportDetail(
      id: _toInt(json['id']),
      title: _toText(json['title']) ?? '',
      periodLabel: _toText(json['period_label']) ?? '',
      periodStart: _toText(json['period_start']),
      periodEnd: _toText(json['period_end']),
      summary: _toText(json['summary']) ?? '',
      createdAt: _toText(json['created_at']),
      content: content is List
          ? content
              .whereType<Map>()
              .map(
                (Map item) =>
                    ReportBlock.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
          : const <ReportBlock>[],
    );
  }
}

/// 报告域配置：列表页/明细页共用，路由里直接传 `ReportSource.finance`。
class ReportSource {
  const ReportSource({
    required this.apiPath,
    required this.pageTitle,
    required this.routeBase,
    required this.emptyDescription,
  });

  /// 接口前缀，如 `/finance/reports`。
  final String apiPath;

  /// 页面标题，如「财务报告」。
  final String pageTitle;

  /// 路由前缀，如 `/finance/reports`。
  final String routeBase;

  /// 列表空态说明。
  final String emptyDescription;

  static const ReportSource finance = ReportSource(
    apiPath: '/finance/reports',
    pageTitle: '财务报告',
    routeBase: '/finance/reports',
    emptyDescription: '暂无财务报告，可在网页端生成',
  );

  static const ReportSource investment = ReportSource(
    apiPath: '/investment/reports',
    pageTitle: '投资报告',
    routeBase: '/invest/reports',
    emptyDescription: '暂无投资报告，可在网页端生成',
  );
}
