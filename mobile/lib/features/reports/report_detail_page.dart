import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';

/// 报告明细页：财务报告 / 投资报告共用。
///
/// 接口：`GET {source.apiPath}/{id}`。
/// 标题只显示报告名（AppBar），统计区间作为副标题只出现一次；
/// 明细按后端区块（h2 + table）分组，宽表改为「首列标题 + 两列字段网格」，
/// 不做横向滚动。
class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.source,
    required this.reportId,
  });

  final ReportSource source;
  final int reportId;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  ReportDetail? _detail;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 每个分组的锚点 key，供「目录」跳转使用；按分组序号复用，避免重建失效。
  final Map<int, GlobalKey> _sectionKeys = <int, GlobalKey>{};

  /// 目录跳转：滚动到对应分组顶部。
  Future<void> _jumpToSection(int index) async {
    final BuildContext? target = _sectionKeys[index]?.currentContext;
    if (target == null) {
      return;
    }
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取单份报告明细。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _status = scope.auth.connectionFailed
            ? LoadStatus.connectionFailed
            : LoadStatus.unauthenticated;
        _message = scope.auth.restoreError;
      });
      return;
    }
    setState(() {
      _status = _detail == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Map<String, dynamic>? data = (await scope.apiClient
              .get<Map<String, dynamic>>(
            '${widget.source.apiPath}/${widget.reportId}',
          ))
          .data;
      if (data == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '报告详情返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = ReportDetail.fromJson(data);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ReportDetail? detail = _detail;
    final String title = detail == null || detail.displayTitle.isEmpty
        ? widget.source.pageTitle
        : detail.displayTitle;
    final List<_ReportSection> sections = detail == null
        ? const <_ReportSection>[]
        : _collectSections(context, detail.content);
    final int totalRows =
        sections.fold<int>(0, (int sum, _ReportSection item) => sum + item.rowCount);
    final int titledSections =
        sections.where((_ReportSection item) => item.title != null).length;
    // 长报告（如财务报告 104 笔购物明细）提供目录，短报告不额外占位。
    final bool showToc = totalRows >= 20 && titledSections >= 2;

    return DetailPageScaffold(
      title: title,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready && detail != null) ...<Widget>[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: <Widget>[
                      if (detail.rangeText.isNotEmpty)
                        Row(
                          spacing: 6,
                          children: <Widget>[
                            Icon(Icons.calendar_month_outlined,
                                size: 16, color: muted),
                            Flexible(
                              child: Text(
                                detail.rangeText,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      // 报告是生成时快照：明确「截至生成日」，避免与当前实时数据混淆。
                      Text(
                        detail.createdText.isEmpty
                            ? '本报告为生成时快照，数据截至生成日，不随当前数据变化。'
                            : '${detail.createdText} · 快照口径：数据截至生成日，不随当前数据变化。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      if (detail.displaySummary.isNotEmpty)
                        Text.rich(
                          _summarySpan(context, detail.displaySummary),
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                if (showToc) _buildToc(context, sections),
                for (int i = 0; i < sections.length; i++)
                  _buildSectionCard(sections[i], i),
                if (detail.content.isEmpty)
                  const SectionCard(
                    child: EmptyState(
                      icon: Icons.description_outlined,
                      title: '报告暂无明细',
                      description: '该报告未包含可展示的区块',
                      compact: true,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 是否按美元口径展示金额（投资报告）。
  bool get _usd => widget.source.usdAmounts;

  /// 金额语义列 / 行关键字；「盈亏比」「胜率」等比率不算金额。
  static const List<String> _moneyKeys = <String>[
    '净收益',
    '毛盈亏',
    '手续费',
    '隔夜费',
    '平均盈利',
    '平均亏损',
    '账户净值',
    '入金',
    '出金',
    '体验金',
    '净盈亏',
    '盈亏',
  ];

  bool _isMoneyLabel(String label) {
    if (label.contains('比') || label.contains('率')) {
      return false;
    }
    return _moneyKeys.any(label.contains);
  }

  /// 给纯数字补 `$`：`1,234.00` → `$1,234.00`、`-1,234.00` → `-$1,234.00`。
  ///
  /// 「入金 / 出金」一行是两段金额，按 ` / ` 拆开分别处理；非数字原样返回。
  String _usdNumber(String raw) {
    final String text = raw.trim();
    if (text.isEmpty || text == '—') {
      return raw;
    }
    final List<String> parts = text.split(' / ');
    bool changed = false;
    final List<String> output = <String>[];
    for (final String part in parts) {
      final Match? match =
          RegExp(r'^([+-])?(\d[\d,]*(?:\.\d+)?)$').firstMatch(part.trim());
      if (match == null) {
        output.add(part);
        continue;
      }
      changed = true;
      // `-0.00` 这类负零去掉符号，避免投资报告出现「-$0.00」。
      final double parsed =
          double.tryParse(match[2]!.replaceAll(',', '')) ?? 0;
      final String sign = parsed == 0 ? '' : (match[1] ?? '');
      output.add('$sign\$${match[2]}');
    }
    return changed ? output.join(' / ') : raw;
  }

  /// 只给明确的金额列 / 金额行补 `$`，笔数、胜率、手数等保持原样。
  List<List<String>> _usdRows(List<String> header, List<List<String>> rows) {
    if (!_usd) {
      return rows;
    }
    return rows.map((List<String> row) {
      final List<String> cells = List<String>.of(row);
      if (header.length <= 2 && !header.any(_isMoneyLabel)) {
        // 「指标 | 数值」型：按首列标签判断这一行是否为金额。
        if (cells.length >= 2 && _isMoneyLabel(cells[0])) {
          cells[1] = _usdNumber(cells[1]);
        }
        return _stripPositions(cells);
      }
      for (int i = 0; i < cells.length && i < header.length; i++) {
        if (_isMoneyLabel(header[i])) {
          cells[i] = _usdNumber(cells[i]);
        }
      }
      return _stripPositions(cells);
    }).toList();
  }

  /// 去掉已完结数据里残留的「（持仓 0）」文案（后端报告正文固定带这个后缀）。
  List<String> _stripPositions(List<String> cells) {
    return cells
        .map((String cell) => cell.replaceAll(
              RegExp(r'[（(]\s*持仓\s*\d+\s*[)）]'),
              '',
            ))
        .toList();
  }

  /// 摘要正文里的金额（净收益 / 账户净值 / 毛盈亏等）补 `$`，
  /// 并按正负着色；「持仓 N」是已完结数据的残留文案，一并去掉。
  String _usdProse(String text) {
    if (!_usd) {
      return text;
    }
    final String withUsd = text.replaceAllMapped(
      RegExp(r'(净收益|账户净值|毛盈亏|入金|出金|体验金)\s+([+-]?\d[\d,]*(?:\.\d+)?)'),
      (Match match) => '${match[1]} ${_usdNumber(match[2]!)}',
    );
    return withUsd.replaceAll(
      RegExp(r'[（(]\s*持仓\s*\d+\s*[)）]'),
      '',
    );
  }

  /// 摘要富文本：只给金额上色（成功绿 / 危险红 / 零中性），其余文字保持正文色。
  TextSpan _summarySpan(BuildContext context, String text) {
    final TextStyle? base = Theme.of(context).textTheme.bodyMedium;
    if (!_usd) {
      return TextSpan(text: text, style: base);
    }
    final AppSemanticColors colors = context.semanticColors;
    final String normalized = _usdProse(text);
    final List<TextSpan> spans = <TextSpan>[];
    int last = 0;
    for (final Match match in RegExp(r'[+-]?\$[\d,]+\.\d{2}').allMatches(normalized)) {
      if (match.start > last) {
        spans.add(TextSpan(text: normalized.substring(last, match.start)));
      }
      final double parsed = double.tryParse(
            match[0]!.replaceAll(RegExp(r'[^\d.\-]'), ''),
          ) ??
          0;
      spans.add(
        TextSpan(
          text: match[0],
          style: TextStyle(
            color: parsed < 0
                ? colors.danger
                : (parsed > 0 ? colors.success : null),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      last = match.end;
    }
    if (last < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(last)));
    }
    return TextSpan(style: base, children: spans);
  }

  /// 把 h2 / table 区块收拢成「标题 + 内容 + 行数」的分组数据。
  List<_ReportSection> _collectSections(
    BuildContext context,
    List<ReportBlock> blocks,
  ) {
    final List<_ReportSection> result = <_ReportSection>[];
    String? sectionTitle;
    final List<Widget> body = <Widget>[];
    int rowCount = 0;

    void flush() {
      if (body.isEmpty) {
        sectionTitle = null;
        rowCount = 0;
        return;
      }
      result.add(
        _ReportSection(
          title: sectionTitle,
          children: List<Widget>.of(body),
          rowCount: rowCount,
        ),
      );
      body.clear();
      sectionTitle = null;
      rowCount = 0;
    }

    for (final ReportBlock block in blocks) {
      if (block.isHeading) {
        flush();
        sectionTitle = block.text;
      } else if (block.isTable) {
        body.add(
          _ReportTable(
            header: block.header,
            rows: _usdRows(block.header, block.rows),
            caption: block.caption,
            colorizePositive: _usd,
          ),
        );
        rowCount += block.rows.length;
      } else if (block.isKv) {
        body.add(
          _ReportTable(
            header: const <String>[],
            rows: _usdRows(const <String>[], block.rows),
            caption: block.caption,
            colorizePositive: _usd,
          ),
        );
        rowCount += block.rows.length;
      } else if ((block.text ?? '').isNotEmpty) {
        body.add(
          Text(block.text!, style: Theme.of(context).textTheme.bodyMedium),
        );
      }
    }
    flush();
    return result;
  }

  /// 单个分组卡片；key 供目录跳转定位。
  Widget _buildSectionCard(_ReportSection section, int index) {
    final GlobalKey key =
        _sectionKeys.putIfAbsent(index, () => GlobalKey());
    return SectionCard(
      key: key,
      title: section.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: section.children,
      ),
    );
  }

  /// 长报告目录：每条分组一行，点击滚动到对应分组。
  Widget _buildToc(BuildContext context, List<_ReportSection> sections) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<Widget> entries = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      final _ReportSection section = sections[i];
      if (section.title == null) {
        continue;
      }
      entries.add(
        InkWell(
          onTap: () => _jumpToSection(i),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              spacing: 8,
              children: <Widget>[
                Expanded(
                  child: Text(
                    section.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (section.rowCount > 0)
                  Text(
                    '${section.rowCount} 项',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                Icon(Icons.chevron_right, size: 18, color: muted),
              ],
            ),
          ),
        ),
      );
    }
    return SectionCard(
      title: '目录',
      trailing: Text(
        '点击跳转到分组',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
      child: Column(children: entries),
    );
  }
}

/// 报告明细的一个分组（h2 + 若干区块）。
class _ReportSection {
  const _ReportSection({
    required this.title,
    required this.children,
    required this.rowCount,
  });

  final String? title;
  final List<Widget> children;

  /// 表格 / 键值对行数，用于目录里标注「N 项」。
  final int rowCount;
}

/// 报告表格渲染：两列走「标签 / 数值」行，多列按首列分组成字段网格。
class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.header,
    required this.rows,
    this.caption = '',
    this.colorizePositive = false,
  });

  final List<String> header;
  final List<List<String>> rows;

  /// 表格小标题（后端 `name`）/ 键值对分组标签（后端 `label`）。
  final String caption;

  /// 正数（不带 `+` 的 `$` 金额）是否也用成功色：投资报告需要，其他域保持原规则。
  final bool colorizePositive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Widget table;
    if (rows.isEmpty) {
      table = Text(
        '暂无数据',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    } else if (header.length <= 2) {
      table = Column(
        children: <Widget>[
          for (final List<String> row in rows)
            _KvRow(
              header: header,
              row: row,
              colorizePositive: colorizePositive,
            ),
        ],
      );
    } else {
      table = Column(
        children: <Widget>[
          for (int index = 0; index < rows.length; index++) ...<Widget>[
            if (index > 0) const Divider(),
            _GroupedRow(
              header: header,
              row: rows[index],
              colorizePositive: colorizePositive,
            ),
          ],
        ],
      );
    }
    if (caption.isEmpty) {
      return table;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: <Widget>[
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        table,
      ],
    );
  }
}

/// 两列表格的一行：左标签、右数值（等宽、正负分色）。
class _KvRow extends StatelessWidget {
  const _KvRow({
    required this.header,
    required this.row,
    this.colorizePositive = false,
  });

  final List<String> header;
  final List<String> row;
  final bool colorizePositive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppSemanticColors colors = context.semanticColors;
    final String label = row.isNotEmpty ? row[0] : '';
    final String value = row.length > 1 ? row[1] : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _signColor(
                  value,
                  colors,
                  colorizePositive: colorizePositive,
                ),
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 多列表格的一行：首列当标题，其余列按两列网格分组展示（不横向滚动）。
class _GroupedRow extends StatelessWidget {
  const _GroupedRow({
    required this.header,
    required this.row,
    this.colorizePositive = false,
  });

  final List<String> header;
  final List<String> row;
  final bool colorizePositive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppSemanticColors colors = context.semanticColors;
    final String title = row.isNotEmpty ? row[0] : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 6,
                children: <Widget>[
                  for (int i = 1; i < header.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: <Widget>[
                          Text(
                            header[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                          Text(
                            i < row.length ? row[i] : '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _signColor(
                                i < row.length ? row[i] : '',
                                colors,
                                colorizePositive: colorizePositive,
                              ),
                              fontWeight: FontWeight.w600,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 数值正负色：`+` 开头用 success，`-` 开头用 danger，其余保持默认色。
///
/// 只在「符号后紧跟数字或货币符号」时生效，避免把日期等文本误判成负数。
Color? _signColor(
  String value,
  AppSemanticColors colors, {
  bool colorizePositive = false,
}) {
  final String text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  if (RegExp(r'^[+＋]\s*(?:¥|￥|\$|\d)').hasMatch(text)) {
    return colors.success;
  }
  if (RegExp(r'^[-−]\s*(?:¥|￥|\$|\d)').hasMatch(text)) {
    return colors.danger;
  }
  // 投资报告里不带 `+` 的美元金额也算正数：> 0 用成功色，$0.00 保持中性。
  if (colorizePositive) {
    final String first = text.split(' / ').first.trim();
    if (RegExp(r'^\$\s*[\d]').hasMatch(first)) {
      final double parsed =
          double.tryParse(first.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
      if (parsed > 0) {
        return colors.success;
      }
    }
  }
  return null;
}
