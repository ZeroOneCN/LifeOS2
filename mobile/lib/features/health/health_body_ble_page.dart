import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import 'ble/body_composition.dart';
import 'ble/scale_session.dart';

/// 蓝牙体重秤页：连接蚂蚁阿福体重秤（AFU-WL-TZ-A1）并写入当天体重。
///
/// 链路移植自网页端 `use-web-bluetooth.ts` + `scale-protocol.ts`：
/// 扫描过滤 → 连接 → 订阅 `FFB2` → 下发资料包 → 解析体重 / 阻抗 → 估算体成分 → `blesync`。
///
/// 四态反馈：扫描（设备列表 / 空态引导）、连接（可取消）、读取（等待上秤 / 读数）、写入（同步中 / 成功）。
/// 失败时提供「重试」与「改用手动录入」，手动录入路径不受影响。
class HealthBodyBlePage extends StatefulWidget {
  const HealthBodyBlePage({super.key});

  @override
  State<HealthBodyBlePage> createState() => _HealthBodyBlePageState();
}

class _HealthBodyBlePageState extends State<HealthBodyBlePage> {
  ScaleSession? _session;
  final TextEditingController _height = TextEditingController(text: '173');
  final TextEditingController _age = TextEditingController(text: '25');
  bool _isMale = true;
  String? _profileError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= ScaleSession(apiClient: AppScope.of(context).apiClient)
      ..addListener(_onSessionChanged);
  }

  /// 会话状态变化后刷新页面。
  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  /// 校验资料并开始扫描。
  Future<void> _startScan() async {
    final ScaleSession? session = _session;
    if (session == null) {
      return;
    }
    final double? height = double.tryParse(_height.text.trim());
    final int? age = int.tryParse(_age.text.trim());
    if (height == null || height < 100 || height > 250) {
      setState(() => _profileError = '身高应在 100~250 cm');
      return;
    }
    if (age == null || age < 1 || age > 120) {
      setState(() => _profileError = '年龄应在 1~120 岁');
      return;
    }
    setState(() => _profileError = null);
    session.setProfile(heightCm: height, age: age, isMale: _isMale);
    await session.startScan();
  }

  /// 权限被永久拒绝时跳系统设置。
  Future<void> _openSettings() async {
    await _session?.permissions.openAppSettings();
  }

  /// 蓝牙关闭时先弹系统开关，开启成功后直接重新扫描。
  Future<void> _enableBluetooth() async {
    final ScaleSession? session = _session;
    if (session == null) {
      return;
    }
    final bool turnedOn = await session.turnOnBluetooth();
    if (turnedOn && mounted) {
      await session.startScan();
    }
  }

  /// 私有服务缺失且未配对时，引导系统配对并重连。
  Future<void> _pairDevice() async {
    await _session?.pairAndReconnect();
  }

  /// 返回体重页并刷新列表与统计。
  void _finish() {
    Navigator.of(context).pop(true);
  }

  /// 蓝牙失败降级为手动录入。
  void _manualEntry() {
    context.pushReplacement('/health/body/new');
  }

  /// 三按钮同行里的「重扫描」次操作（无图标，宽度全留给文字）。
  Widget get _errorRescanButton => AppSecondaryButton(
        label: '重扫描',
        compact: true,
        onPressed: _startScan,
      );

  /// 三按钮同行里的「手动录入」次操作（蓝牙失败时的降级通道）。
  Widget get _errorManualButton => AppSecondaryButton(
        label: '手动录入',
        compact: true,
        onPressed: _manualEntry,
      );

  @override
  Widget build(BuildContext context) {
    final ScaleSession? session = _session;
    return DetailPageScaffold(
      title: '蓝牙体重秤',
      bottomBar: session == null ? null : _bottomBar(session),
      child: session == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                _statusCard(session),
                const SizedBox(height: 12),
                _profileCard(session),
                const SizedBox(height: 12),
                if (session.stage == ScaleStage.scanning ||
                    (session.stage == ScaleStage.idle &&
                        session.devices.isNotEmpty))
                  _deviceCard(session),
                if (session.error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _messageCard(
                    text: session.error!,
                    icon: Icons.error_outline,
                    isError: true,
                  ),
                ],
                if (session.hint != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _messageCard(
                    text: session.hint!,
                    icon: Icons.lightbulb_outline,
                    isError: false,
                  ),
                ],
                if (session.reading != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _readingCard(session.reading!),
                ],
                const SizedBox(height: 12),
                _notesCard(),
                const SizedBox(height: 12),
                _debugCard(session),
              ],
            ),
    );
  }

  /// 状态卡：当前阶段 + 说明，四态都能看到自己在哪一步。
  Widget _statusCard(ScaleSession session) {
    final ThemeData theme = Theme.of(context);
    final (String title, String detail, IconData icon) = _stageText(session);
    return SectionCard(
      title: '连接状态',
      child: Row(
        spacing: 12,
        children: <Widget>[
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 阶段 → 文案 / 图标。
  (String, String, IconData) _stageText(ScaleSession session) {
    switch (session.stage) {
      case ScaleStage.idle:
        return (
          '未连接',
          session.devices.isEmpty
              ? '点下方「扫描设备」开始；建议先踩一下秤面唤醒。'
              : '已发现设备，点选下方设备连接。',
          Icons.bluetooth_searching,
        );
      case ScaleStage.scanning:
        return (
          '扫描中…',
          '只显示广播中带私有服务 0xFFB0 或名称含 AFU / UAF028 的设备。',
          Icons.bluetooth_searching,
        );
      case ScaleStage.connecting:
        return (
          '连接中…',
          '正在建立 GATT 连接并订阅 FFB2 通知，请保持秤在附近。',
          Icons.bluetooth_connected,
        );
      case ScaleStage.waiting:
        return (
          '等待上秤',
          '已连接，请光脚站上秤并保持双脚覆盖电极 5~8 秒。',
          Icons.monitor_weight_outlined,
        );
      case ScaleStage.measured:
        return ('已读取', '读数已就绪，可同步到今天，也可重新称重。', Icons.check_circle_outline);
      case ScaleStage.syncing:
        return ('写入中…', '正在提交到健康中心（按服务器今天覆盖）。', Icons.cloud_upload_outlined);
      case ScaleStage.synced:
        return ('已同步', '体重与体成分已写入今天的体重记录。', Icons.cloud_done_outlined);
      case ScaleStage.error:
        return ('出现问题', '可按下方按钮重试，或改用手动录入。', Icons.error_outline);
    }
  }

  /// 资料卡：身高 / 年龄 / 性别，连接后锁定，与网页端口径一致。
  Widget _profileCard(ScaleSession session) {
    final ThemeData theme = Theme.of(context);
    final bool locked = session.connected;
    return SectionCard(
      title: '测量资料',
      trailing: Text(
        locked ? '已锁定' : '用于体成分与阻抗测量',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          Row(
            spacing: 12,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _height,
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '身高',
                    suffixText: 'cm',
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _age,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '年龄',
                    suffixText: '岁',
                  ),
                ),
              ),
            ],
          ),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('男')),
              ButtonSegment<bool>(value: false, label: Text('女')),
            ],
            selected: <bool>{_isMale},
            onSelectionChanged: locked
                ? null
                : (Set<bool> selection) {
                    setState(() => _isMale = selection.first);
                  },
          ),
          if (_profileError != null)
            Text(
              _profileError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  /// 设备卡：名称 + 信号强度，空列表时给唤醒引导。
  Widget _deviceCard(ScaleSession session) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: '发现的设备',
      trailing: Text(
        '${session.devices.length} 台',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: session.devices.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                session.stage == ScaleStage.scanning
                    ? '正在扫描…请确认秤已进入可连接状态（踩一下秤面即可唤醒）。'
                    : '没有发现体重秤。请踩一下秤面唤醒后重新扫描。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final ScaleDeviceOption option in session.devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.monitor_weight_outlined),
                    title: Text(option.name),
                    subtitle: Text(
                      '信号 ${option.rssi} dBm · ${option.remoteId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        session.stage == ScaleStage.scanning ||
                            session.stage == ScaleStage.idle
                        ? () => session.connect(option)
                        : null,
                  ),
              ],
            ),
    );
  }

  /// 读数卡：体重必显，体成分有则显示；未采集阻抗时明确说明。
  Widget _readingCard(ScaleReading reading) {
    final ThemeData theme = Theme.of(context);
    final BodyCompositionResult? body = reading.bodyComposition;
    return SectionCard(
      title: '本次测量',
      trailing: Text(
        _timeText(reading.measuredAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 2,
            children: <Widget>[
              Text(
                reading.weightKg.toStringAsFixed(2),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                'kg',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (body == null)
            Text(
              reading.impedanceOhm == null
                  ? '未采集到阻抗（可能未光脚或本次未触发电极测量），体成分不写入，避免写入 0。'
                  : '本次未估算体成分。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...<Widget>[
            Row(
              spacing: 12,
              children: <Widget>[
                Expanded(child: _metric('BMI', body.bmi.toStringAsFixed(1))),
                Expanded(
                  child: _metric('体脂率', '${body.bodyFat.toStringAsFixed(1)}%'),
                ),
              ],
            ),
            Row(
              spacing: 12,
              children: <Widget>[
                Expanded(
                  child: _metric('肌肉量', '${body.muscle.toStringAsFixed(1)} kg'),
                ),
                Expanded(child: _metric('基础代谢', '${body.bmr} kcal')),
              ],
            ),
            if (reading.impedanceOhm != null)
              Text(
                '阻抗 ${reading.impedanceOhm!.toStringAsFixed(1)} Ω · '
                '体成分由体重与阻抗本地估算，仅供参考。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 单个指标块。
  Widget _metric(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 提示 / 错误卡片。
  Widget _messageCard({
    required String text,
    required IconData icon,
    required bool isError,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final Color foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: foreground),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  /// 口径说明与局限。
  Widget _notesCard() {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: '说明与局限',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: <Widget>[
          Text(
            '· 本页仅支持蚂蚁阿福体重秤 AFU-WL-TZ-A1（广播名 UAF028，私有服务 0xFFB0）。'
            '小米 / 华为 / 云麦等厂商私有协议的秤无法通过本页连接。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '· 同一台秤同一时间只能被一个程序占用；若后端采集器 '
            'ENABLE_SCALE_COLLECTOR 正在运行，请先关闭并重启后端，否则手机收不到称重数据。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '· 写入按服务器「今天」覆盖，measured_at 不参与定位；跨天称重可能覆盖当天记录，请注意。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '· 未采集到阻抗或体成分时只写体重，不会用 0 覆盖历史数据。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作区：随阶段切换，扫描 / 连接阶段始终可取消。
  Widget _bottomBar(ScaleSession session) {
    switch (session.stage) {
      case ScaleStage.scanning:
        return AppSecondaryButton(
          label: '取消扫描',
          icon: Icons.close,
          onPressed: session.stopScan,
        );
      case ScaleStage.connecting:
        return AppSecondaryButton(
          label: '取消连接',
          icon: Icons.close,
          onPressed: session.disconnect,
        );
      case ScaleStage.waiting:
        return AppActionRow(
          first: AppPrimaryButton(
            label: '等待上秤…',
            icon: Icons.monitor_weight_outlined,
            onPressed: null,
          ),
          second: AppSecondaryButton(
            label: '断开',
            icon: Icons.bluetooth_disabled,
            onPressed: session.disconnect,
          ),
        );
      case ScaleStage.measured:
        // 三个动作：写入是唯一主操作，独占整行；「重新称重 / 断开」同级并列，走 AppActionRow。
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: <Widget>[
            AppPrimaryButton(
              label: '同步到健康中心',
              icon: Icons.cloud_upload_outlined,
              onPressed: session.syncToServer,
            ),
            AppActionRow(
              first: AppSecondaryButton(
                label: '重新称重',
                icon: Icons.refresh,
                onPressed: session.startScan,
              ),
              second: AppSecondaryButton(
                label: '断开',
                icon: Icons.bluetooth_disabled,
                onPressed: session.disconnect,
              ),
            ),
          ],
        );
      case ScaleStage.syncing:
        return AppPrimaryButton(
          label: '正在写入…',
          icon: Icons.cloud_upload_outlined,
          loading: true,
          onPressed: null,
        );
      case ScaleStage.synced:
        // 完成 / 再称一次 是同级并列动作，统一走 AppActionRow 保证 1:1 等宽等高。
        return AppActionRow(
          first: AppPrimaryButton(
            label: '返回体重',
            icon: Icons.check,
            onPressed: _finish,
          ),
          second: AppSecondaryButton(
            label: '再称一次',
            icon: Icons.refresh,
            onPressed: session.startScan,
          ),
        );
      case ScaleStage.error:
        // 修复动作 + 降级通道放在同一行 1:1:1 三等宽。
        // 窄屏（375 + 1.3x）每个槽位只有约 106 逻辑像素，因此：
        // 文案压到 3~4 字（开蓝牙 / 重扫描 / 手动录入）、去掉图标、
        // 用紧凑高度（36），把宽度全留给文字，且仍留出余量不折行。
        if (session.needsPairing) {
          return AppActionRow(
            first: AppPrimaryButton(
              label: '配对该秤',
              icon: null,
              compact: true,
              onPressed: _pairDevice,
            ),
            second: _errorRescanButton,
            third: _errorManualButton,
          );
        }
        if (session.permissionBlocked) {
          return AppActionRow(
            first: AppPrimaryButton(
              label: '去设置',
              icon: null,
              compact: true,
              onPressed: _openSettings,
            ),
            second: AppSecondaryButton(
              label: '重授权',
              compact: true,
              onPressed: _startScan,
            ),
            third: _errorManualButton,
          );
        }
        if (session.bluetoothOff) {
          return AppActionRow(
            first: AppPrimaryButton(
              label: '开蓝牙',
              icon: null,
              compact: true,
              onPressed: _enableBluetooth,
            ),
            second: _errorRescanButton,
            third: _errorManualButton,
          );
        }
        // 兜底错误只有「重扫描 / 手动录入」两个动作，不硬凑第三个按钮。
        return AppActionRow(
          first: AppPrimaryButton(
            label: '重扫描',
            icon: null,
            compact: true,
            onPressed: _startScan,
          ),
          second: _errorManualButton,
        );
      case ScaleStage.idle:
        return AppActionRow(
          first: AppPrimaryButton(
            label: '扫描设备',
            icon: Icons.bluetooth_searching,
            onPressed: _startScan,
          ),
          second: AppSecondaryButton(
            label: '手动录入',
            icon: Icons.edit_outlined,
            onPressed: _manualEntry,
          ),
        );
    }
  }

  /// 调试信息卡：原样展示 GATT 服务枚举与收到的原始通知帧，便于真机取证。
  Widget _debugCard(ScaleSession session) {
    final ThemeData theme = Theme.of(context);
    final List<String> lines = <String>[
      ...session.gattLog,
      if (session.frameLog.isNotEmpty) '--- 原始通知帧 ---',
      ...session.frameLog,
    ];
    return SectionCard(
      title: '调试信息',
      trailing: Text(
        '排查用',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'GATT 服务 / 原始帧（${session.gattLog.length} / ${session.frameLog.length}）',
          style: theme.textTheme.bodySmall,
        ),
        children: <Widget>[
          if (lines.isEmpty)
            Text(
              '连接后这里会列出 discoverServices 返回的全部服务与特征 UUID，以及 FFB2 原始帧。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  lines.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `HH:mm:ss`。
  String _timeText(DateTime time) {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
