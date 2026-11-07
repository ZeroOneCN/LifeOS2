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
        : _collectSections(context, detail.content, title);
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

  /// 是否为健康报告（正文用 `-` 表示空值）。
  bool get _health => identical(widget.source, ReportSource.health);

  /// 是否为生活报告（价格列缺 `¥`、`正常 / 总数 张` 等格式需要归一）。
  bool get _life => identical(widget.source, ReportSource.lifestyle);

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
      // 快照里的大数字可能没带千分位（如 `3770`），展示前统一补齐。
      output.add('$sign\$${_groupDigits(match[2]!)}');
    }
    return changed ? output.join(' / ') : raw;
  }

  /// 给纯数字补千分位：`3770` → `3,770`；已带逗号或不足四位原样返回。
  static String _groupDigits(String number) {
    if (number.contains(',')) {
      return number;
    }
    final List<String> parts = number.split('.');
    final String intPart = parts.first;
    if (intPart.length <= 3) {
      return number;
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
    }
    return parts.length > 1 ? '$buffer.${parts[1]}' : '$buffer';
  }

  /// 正文 / 表格里独立的四位以上整数补千分位。
  ///
  /// 排除日期（`2026-07-10`、`2026年09月`）、时间（`18:52`）、小数、百分比与负号，
  /// 只处理「3770」这种裸整数，避免把年份写成「2,026」。
  static String _groupPlainNumbers(String text) {
    if (text.isEmpty || text == '—') {
      return text;
    }
    return text.replaceAllMapped(
      RegExp(r'(?<![\d,.\-:/])(\d{4,})(?![\d.\-:/%年月日时分秒])'),
      (Match match) => _groupDigits(match[1]!),
    );
  }

  /// 健康报告的后端正文用单个 `-` 表示空值，展示前统一成「—」。
  ///
  /// 只替换「独立成值」的 hyphen：`-/- mmHg`、`- %`、`- mmol/L`、单独的 `-`；
  /// 时间范围 `18:52 - 04:42` 的连字符与负号 `-1.7`、日期 `2026-07-10` 保持不变。
  String _normalizeDashes(String text) {
    if (text.isEmpty) {
      return text;
    }
    // 先保护时间范围里的分隔连字符，稍后原样还原。
    const String guard = '\u0001';
    final String protectedText = text.replaceAllMapped(
      RegExp(r'(\d{1,2}:\d{2})\s+-\s+(\d{1,2}:\d{2})'),
      (Match match) => '${match[1]}$guard${match[2]}',
    );
    final String replaced = protectedText.replaceAllMapped(
      RegExp(r'(^|[\s/])[-−](?=[\s/]|$|[A-Za-z%°])'),
      (Match match) => '${match[1]}—',
    );
    return replaced.replaceAll(guard, ' - ');
  }

  /// 健康报告：把表格与键值对所有单元格做一次空值符号归一。
  List<List<String>> _healthRows(List<List<String>> rows) {
    if (!_health) {
      return rows;
    }
    return rows
        .map((List<String> row) => row.map(_normalizeDashes).toList())
        .toList();
  }

  /// 生活报告摘要做展示归一：修掉重复词与未解释的「≈」，并按分句主动换行。
  ///
  /// 「待办待处理」是后端模板把「待办」「待处理」拼在一起的产物，读起来像结巴；
  /// 「（≈）」没有说明估算口径，直接展开成「（估算）」。这两处只改展示，不动数据。
  String _lifeSummary(String text) {
    return text
        .replaceAll('待办待处理', '待办事项')
        .replaceAll('（≈）', '（估算）')
        .replaceAll('(≈)', '（估算）')
        .replaceAll('，', '，\n')
        .trimRight();
  }

  /// 表格单元格 / 表头的用词归一：只换词不换行（表格里不能插换行）。
  ///
  /// 生活报告的「有效物品日均成本合计（≈）」里的 ≈ 没有说明，展开成「（估算）」。
  String _cellText(String text) {
    if (text.isEmpty) {
      return text;
    }
    return text
        .replaceAll('待办待处理', '待办事项')
        .replaceAll('（≈）', '（估算）')
        .replaceAll('(≈)', '（估算）');
  }

  /// 整行单元格归一。
  List<String> _rowText(List<String> row) =>
      row.map(_cellText).toList(growable: false);

  /// 正文段落展示归一：健康报告补空值符号，生活报告折叠重复词并主动断句。
  String _bodyText(String text) {
    if (_health) {
      return _normalizeDashes(text);
    }
    if (_life) {
      return _lifeSummary(text);
    }
    return text;
  }

  /// 生活报告的展示归一：价格列补 `¥`；「正常 / 总数 张」相等时收敛成「N 张」。
  List<List<String>> _lifeRows(List<String> header, List<List<String>> rows) {
    if (!_life) {
      return rows;
    }
    final int priceIndex = header.indexOf('价格');
    return rows.map((List<String> row) {
      final List<String> cells = List<String>.of(row);
      if (priceIndex >= 0 && priceIndex < cells.length) {
        final String price = cells[priceIndex].trim();
        if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(price)) {
          cells[priceIndex] = '¥$price';
        }
      }
      for (int i = 0; i < cells.length; i++) {
        final Match? ratio = RegExp(
          r'^(\d+)\s*/\s*(\d+)\s*(张|件|台|个)$',
        ).firstMatch(cells[i].trim());
        if (ratio != null) {
          cells[i] = ratio[1] == ratio[2]
              ? '${ratio[1]} ${ratio[3]}'
              : '${ratio[1]} / ${ratio[2]} ${ratio[3]}';
        }
      }
      return cells;
    }).toList();
  }

  /// 只给明确的金额列 / 金额行补 `$`，笔数、胜率、手数等保持原样。
  List<List<String>> _usdRows(List<String> header, List<List<String>> rows) {
    final List<List<String>> prepareRows =
        _lifeRows(header, _healthRows(rows));
    if (!_usd) {
      return prepareRows;
    }
    return prepareRows.map((List<String> row) {
      final List<String> cells = List<String>.of(row);
      if (header.length <= 2 && !header.any(_isMoneyLabel)) {
        // 「指标 | 数值」型：按首列标签判断这一行是否为金额。
        if (cells.length >= 2 && _isMoneyLabel(cells[0])) {
          cells[1] = _usdNumber(cells[1]);
        }
        return _stripPositions(cells).map(_groupPlainNumbers).toList();
      }
      for (int i = 0; i < cells.length && i < header.length; i++) {
        if (_isMoneyLabel(header[i])) {
          cells[i] = _usdNumber(cells[i]);
        }
      }
      return _stripPositions(cells).map(_groupPlainNumbers).toList();
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
    return withUsd
        .replaceAll(
          RegExp(r'[（(]\s*持仓\s*\d+\s*[)）]'),
          '',
        )
        .replaceAllMapped(
          RegExp(r'(\d{4,})(?![\d.\-:/%年月日时分秒])'),
          (Match match) => _groupDigits(match[1]!),
        );
  }

  /// 摘要富文本：只给金额上色（成功绿 / 危险红 / 零中性），其余文字保持正文色。
  TextSpan _summarySpan(BuildContext context, String text) {
    final TextStyle? base = Theme.of(context).textTheme.bodyMedium;
    if (!_usd) {
      return TextSpan(
        text: _health
            ? _normalizeDashes(text)
            : (_life ? _lifeSummary(text) : text),
        style: base,
      );
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
      // 金额前面紧邻的词决定语义：出金用危险色，入金用成功色，
      // 「净收益 / 账户净值」等仍按正负着色。
      final String prefix = normalized.substring(
        match.start > 8 ? match.start - 8 : 0,
        match.start,
      );
      final bool isOut = prefix.contains('出金');
      final bool isIn = prefix.contains('入金');
      final Color? color;
      if (isOut && !isIn) {
        color = colors.danger;
      } else if (isIn && !isOut) {
        color = colors.success;
      } else {
        color = parsed < 0
            ? colors.danger
            : (parsed > 0 ? colors.success : null);
      }
      // 负号与金额之间插一个不可断字符（U+2060）：1.3 倍字号下正文折行时
      // 会出现「净收益 -」换行、`$1,624.12` 掉到下一行的情况。
      final String amount = match[0]!;
      final bool signed = amount.startsWith('-') || amount.startsWith('+');
      final String amountText = signed
          ? '${amount.substring(0, 1)}\u2060${amount.substring(1)}'
          : amount;
      spans.add(
        TextSpan(
          text: amountText,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
  ///
  /// [pageTitle] 用于去掉正文首个标题与页头重复的情况（如页头「投资报告」+
  /// 正文首个 h2「投资报告」），避免同一屏出现两遍同名标题。
  List<_ReportSection> _collectSections(
    BuildContext context,
    List<ReportBlock> blocks,
    String pageTitle,
  ) {
    final List<_ReportSection> result = <_ReportSection>[];
    String? sectionTitle;
    final List<Widget> body = <Widget>[];
    int rowCount = 0;
    bool firstHeading = true;

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
        final bool duplicate =
            firstHeading && _isReportTitleHeading(block.text ?? '', pageTitle);
        firstHeading = false;
        if (duplicate) {
          // 与页头同名的首个标题直接丢弃，正文内容归入无标题分组。
          continue;
        }
        flush();
        sectionTitle = block.text;
      } else if (block.isTable) {
        final List<String> header = block.header.map(_cellText).toList();
        body.add(
          _ReportTable(
            header: header,
            rows: _usdRows(header, block.rows.map(_rowText).toList()),
            caption: _cellText(block.caption),
            colorizePositive: _usd,
          ),
        );
        rowCount += block.rows.length;
      } else if (block.isKv) {
        body.add(
          _ReportTable(
            header: const <String>[],
            rows: _usdRows(const <String>[], block.rows.map(_rowText).toList()),
            caption: _cellText(block.caption),
            colorizePositive: _usd,
          ),
        );
        rowCount += block.rows.length;
      } else if ((block.text ?? '').isNotEmpty) {
        final String text = block.text!;
        body.add(
          Text(
            _bodyText(text),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }
    }
    flush();
    return result;
  }

  /// 正文标题是否就是页头标题（忽略序号与空白，允许页头只是标题的一部分）。
  static bool _isReportTitleHeading(String heading, String pageTitle) {
    String normalize(String value) => value
        .replaceAll(RegExp(r'^[一二三四五六七八九十\d]+[、.．]\s*'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    final String a = normalize(heading);
    final String b = normalize(pageTitle);
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    return a == b || (a.contains(b) && a.length - b.length <= 12);
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
              // 字段名只在首行出现一次，避免「金额 / 占比」逐行重复。
              showLabels: index == 0,
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
    final String value = row.length > 1 ? _keepUnit(row[1]) : '';
    // 「18 件（花费 ¥256.88）」这类长值，若任其折行会断成「18 件（花费 / ¥256.88）」；
    // 主动在括号前换行，读起来是「数值 + 补充说明」两行。
    final String displayValue = value.length > 12 && value.contains('（')
        ? value.replaceFirst('（', '\n（')
        : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          // 左侧标签多为 6-7 个汉字（「手机卡余额合计」「银行卡（正常）」），
          // 1.3x 下 4:5 会把标签挤成两行，改成 5:4。
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _labelColor(
                  label,
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
    this.showLabels = true,
  });

  final List<String> header;
  final List<String> row;
  final bool colorizePositive;

  /// 是否显示字段名；同组只有首行显示，其余行只列值。
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppSemanticColors colors = context.semanticColors;
    final String title = row.isNotEmpty ? row[0] : '';
    // 体检类表格用「偏高 / 偏低」描述状态；整行都是黑色时用户得逐字读，
    // 这里让异常数值与状态一起带上语义色（偏高红、偏低橙）。
    final bool high = row.any((String cell) => cell.contains('偏高'));
    final bool low = row.any((String cell) => cell.contains('偏低'));
    final Color abnormalColor = high ? colors.danger : colors.warning;
    Color? cellColor(String cell) {
      if (cell.contains('偏高')) {
        return colors.danger;
      }
      if (cell.contains('偏低')) {
        return colors.warning;
      }
      if ((high || low) && RegExp(r'^[-+]?[\d.]').hasMatch(cell.trim())) {
        return abnormalColor;
      }
      return _signColor(cell, colors, colorizePositive: colorizePositive);
    }
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
                          if (showLabels)
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
                              color: cellColor(i < row.length ? row[i] : ''),
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

/// 数字与单位之间换成不换行空格，避免「-1.7 kg」被拆成两行只剩单位。
String _keepUnit(String text) {
  return text.replaceAllMapped(
    RegExp(r'(?<=[0-9)）])\s+(?=[A-Za-zµμ%°])'),
    (Match _) => '\u00A0',
  );
}

/// 先按行标签判断资金语义，再回退到正负色。
///
/// 语义优先于符号：后端把「平均亏损」记成正数（`+$11.69`）时，
/// 仍必须用危险色，不能因为带 `+` 就显示成盈利绿。
/// 比率类（盈亏比 / 胜率 / 盈利因子）本身没有盈亏方向，保持中性。
/// 「入金 / 出金」是两种相反语义合在同一行，整体不着色；
/// 单独的「出金」用危险色、「入金」用成功色，避免出现「出金 = 盈利绿」。
Color? _labelColor(
  String label,
  String value,
  AppSemanticColors colors, {
  bool colorizePositive = false,
}) {
  if (label.contains('比') || label.contains('率') || label.contains('因子')) {
    return null;
  }
  final bool hasIn = label.contains('入金') || label.contains('盈利');
  final bool hasOut = label.contains('出金') || label.contains('亏损');
  if (hasIn && hasOut) {
    return null;
  }
  if (hasOut) {
    return colors.danger;
  }
  if (hasIn) {
    return colors.success;
  }
  return _signColor(value, colors, colorizePositive: colorizePositive);
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
  // 财务报告的负数写作 `¥-5,703.63`（货币符号在前），
  // 所以既要认 `-$1.00`，也要认 `¥-1.00`。
  final Match? sign = RegExp(
    r'^([+＋\-−])?\s*(?:¥|￥|\$)?\s*([+＋\-−])?\s*[\d]',
  ).firstMatch(text);
  if (sign != null) {
    final String? symbol = sign[1] ?? sign[2];
    if (symbol == '+' || symbol == '＋') {
      return colors.success;
    }
    if (symbol == '-' || symbol == '−') {
      return colors.danger;
    }
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
