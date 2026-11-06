/// 离线队列的数据模型与操作类型常量。
///
/// 队列持久化在 `SharedPreferences`（键 `outbox.queue.v1`）：
/// 体积小、冷启动可直接读取、状态字段可整条更新，无需引入数据库。
library;

/// 操作类型：财务记一笔支出（`POST /finance/shopping/records`）。
const String outboxOpCreateExpense = 'finance.shopping.create';

/// 操作类型：用药打卡（`PUT /health/medication/{id}`，按记录 id 幂等更新三餐状态）。
const String outboxOpMedicationCheckin = 'health.medication.checkin';

/// 操作类型：新增外汇交易（`POST /investment/forex`）。
const String outboxOpForexCreate = 'investment.forex.create';

/// 队列中的一条待同步操作。
///
/// 字段对应需求：本地 id、操作类型、请求体、创建时间、重试次数、最后错误。
class OutboxEntry {
  const OutboxEntry({
    required this.localId,
    required this.opType,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
  });

  /// 本地唯一 id（客户端生成的幂等标识，冷启动后不变）。
  final String localId;

  /// 操作类型，见 [outboxOpCreateExpense]。
  final String opType;

  /// 请求体，直接作为 `POST` 的 JSON body。
  final Map<String, dynamic> payload;

  /// 创建时间（ISO8601）。
  final String createdAt;

  /// 已尝试推送次数（每次失败 +1）。
  final int retryCount;

  /// 最后一次失败原因；为 null 表示尚未失败。
  final String? lastError;

  /// 复制并更新重试信息。
  OutboxEntry copyWith({int? retryCount, String? lastError}) {
    return OutboxEntry(
      localId: localId,
      opType: opType,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  /// 序列化为可持久化的 JSON。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'local_id': localId,
      'op_type': opType,
      'payload': payload,
      'created_at': createdAt,
      'retry_count': retryCount,
      'last_error': lastError,
    };
  }

  /// 从持久化 JSON 还原；缺字段时按空值兜底，避免旧数据导致启动失败。
  factory OutboxEntry.fromJson(Map<String, dynamic> json) {
    final Object? rawPayload = json['payload'];
    return OutboxEntry(
      localId: json['local_id'] as String? ?? '',
      opType: json['op_type'] as String? ?? '',
      payload: rawPayload is Map
          ? rawPayload.cast<String, dynamic>()
          : <String, dynamic>{},
      createdAt: json['created_at'] as String? ?? '',
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}
