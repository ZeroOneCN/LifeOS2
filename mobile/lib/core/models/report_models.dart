/// 报告域模型：财务 / 投资 / 健康 / 生活报告列表与明细。
///
/// 字段与网页端 `pages/{finance,investment,health,lifestyle}/reports.tsx` 对齐：
/// - 列表：`GET /finance/reports`、`GET /investment/reports`、`GET /lifestyle/reports`
///   返回数组；`GET /health/reports` 返回分页对象 `{items,total}`；
/// - 明细：`GET {apiPath}/{id}`；
/// - 明细 `content`：财务/投资/生活为区块数组，健康为 JSON 字符串
///   （`{"type":"h2","text":...}`、`{"type":"kv","rows":[[...]]}`、
///   `{"type":"table","header":[...],"rows":[[...]]}`、`{"type":"paragraph","text":...}`）。
library;

import 'dart:convert';

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

/// 从报告标题里提取统计区间：健康报告的接口没有 `period_*` 字段，
/// 区间只存在于标题（`健康报告（2026-07-13 至 2026-10-10）`）。
///
/// 返回统一格式 `yyyy-MM-dd ~ yyyy-MM-dd`；标题不含区间时返回空串。
String reportRangeFromTitle(String? title) {
  if (title == null || title.isEmpty) {
    return '';
  }
  final Match? paren = RegExp(
    r'[（(](\d{4}-\d{2}-\d{2})\s*(?:~|至)\s*(\d{4}-\d{2}-\d{2})[）)]',
  ).firstMatch(title);
  if (paren != null) {
    return '${paren.group(1)} ~ ${paren.group(2)}';
  }
  final Match? prefix = RegExp(
    r'^(\d{4}-\d{2}-\d{2})\s*~\s*(\d{4}-\d{2}-\d{2})',
  ).firstMatch(title);
  if (prefix != null) {
    return '${prefix.group(1)} ~ ${prefix.group(2)}';
  }
  return '';
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
///
/// 财务/投资/生活报告的列表项带 `period_*` 字段；健康报告只有标题内的区间，
/// 因此 [rangeText] 先取字段、再回退到标题解析。
class ReportSummaryItem {
  const ReportSummaryItem({
    required this.id,
    required this.title,
    this.periodLabel = '',
    this.periodStart,
    this.periodEnd,
    this.createdAt,
  });

  final int id;
  final String title;
  final String periodLabel;
  final String? periodStart;
  final String? periodEnd;
  final String? createdAt;

  /// 只含报告名的标题（区间交给副标题）。
  String get displayTitle => reportTitle(title);

  /// 副标题：统计区间（字段缺失时从标题提取），只出现一次。
  String get rangeText {
    final String direct = reportRange(
      start: periodStart,
      end: periodEnd,
      label: periodLabel,
    );
    return direct.isNotEmpty ? direct : reportRangeFromTitle(title);
  }

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
      periodStart: _toText(json['period_start']),
      periodEnd: _toText(json['period_end']),
      createdAt: _toText(json['created_at']),
    );
  }
}

/// 报告内容区块：标题（h2）、键值对（kv）、表格（table）或段落。
///
/// - 健康报告的表格常无 `header`（默认「项目 / 数值」两列），并带 `name` 小标题；
/// - 健康报告的 `kv` 可能带 `label`（如「低库存提醒」）。
class ReportBlock {
  const ReportBlock({
    required this.type,
    this.text,
    this.name,
    this.label,
    this.header = const <String>[],
    this.rows = const <List<String>>[],
  });

  final String type;
  final String? text;

  /// 表格/键值对小标题（后端 `name`），如「最新体征」。
  final String? name;

  /// 键值对分组标签（后端 `label`），如「低库存提醒」。
  final String? label;
  final List<String> header;
  final List<List<String>> rows;

  bool get isHeading => type == 'h2';
  bool get isTable => type == 'table';
  bool get isKv => type == 'kv';

  /// 区块上方的小标题：表格取 `name`，键值对取 `label`。
  String get caption {
    final String value = isKv ? (label ?? '') : (name ?? '');
    return value;
  }

  factory ReportBlock.fromJson(Map<String, dynamic> json) {
    final Object? header = json['header'];
    final Object? rows = json['rows'];
    return ReportBlock(
      type: _toText(json['type']) ?? '',
      text: _toText(json['text']),
      name: _toText(json['name']),
      label: _toText(json['label']),
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

  /// 区间文案（只在副标题出现一次）：优先 `period_*`，缺失时从标题提取。
  String get rangeText {
    final String direct = reportRange(
      start: periodStart,
      end: periodEnd,
      label: periodLabel,
    );
    return direct.isNotEmpty ? direct : reportRangeFromTitle(title);
  }

  /// 去掉区间前缀后的摘要。
  String get displaySummary => reportSummaryText(summary);

  /// 生成时间文案。
  String get createdText {
    final String text = reportDateTime(createdAt);
    return text.isEmpty ? '' : '生成于 $text';
  }

  factory ReportDetail.fromJson(Map<String, dynamic> json) {
    return ReportDetail(
      id: _toInt(json['id']),
      title: _toText(json['title']) ?? '',
      periodLabel: _toText(json['period_label']) ?? '',
      periodStart: _toText(json['period_start']),
      periodEnd: _toText(json['period_end']),
      summary: _toText(json['summary']) ?? '',
      createdAt: _toText(json['created_at']),
      content: _parseContent(json['content']),
    );
  }
}

/// 解析报告内容：财务/投资/生活为区块数组，健康报告为 JSON 字符串。
List<ReportBlock> _parseContent(Object? content) {
  Object? value = content;
  if (value is String) {
    final String text = value.trim();
    if (text.isEmpty) {
      return const <ReportBlock>[];
    }
    try {
      value = jsonDecode(text);
    } on FormatException {
      return const <ReportBlock>[];
    }
  }
  if (value is! List) {
    return const <ReportBlock>[];
  }
  return value
      .whereType<Map>()
      .map((Map item) => ReportBlock.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 报告域配置：列表页/明细页共用，路由里直接传 `ReportSource.finance`。
class ReportSource {
  const ReportSource({
    required this.apiPath,
    required this.pageTitle,
    required this.routeBase,
    required this.emptyDescription,
    this.listPaginated = false,
  });

  /// 接口前缀，如 `/finance/reports`。
  final String apiPath;

  /// 页面标题，如「财务报告」。
  final String pageTitle;

  /// 路由前缀，如 `/finance/reports`。
  final String routeBase;

  /// 列表空态说明。
  final String emptyDescription;

  /// 列表接口是否分页（健康报告返回 `{items,total}`，其余返回数组）。
  final bool listPaginated;

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

  static const ReportSource health = ReportSource(
    apiPath: '/health/reports',
    pageTitle: '健康报告',
    routeBase: '/health/reports',
    emptyDescription: '暂无健康报告，可在网页端生成',
    listPaginated: true,
  );

  static const ReportSource lifestyle = ReportSource(
    apiPath: '/lifestyle/reports',
    pageTitle: '生活报告',
    routeBase: '/life/reports',
    emptyDescription: '暂无生活报告，可在网页端生成',
  );
}
