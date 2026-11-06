/// 数值格式化：统一千分位与金额两位小数，供各域总览摘要复用。
String _group(String digits) {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 整数千分位；null 或无法解析时返回 `--`。
String formatInt(num? value) {
  if (value == null) {
    return '--';
  }
  final String sign = value < 0 ? '-' : '';
  return '$sign${_group(value.round().abs().toString())}';
}

/// 金额：`¥1,286.50`；负数显示为 `-¥1,286.50`。
String formatMoney(num? value) {
  if (value == null) {
    return '--';
  }
  final String fixed = value.abs().toStringAsFixed(2);
  final int dot = fixed.indexOf('.');
  final String sign = value < 0 ? '-' : '';
  return '$sign¥${_group(fixed.substring(0, dot))}${fixed.substring(dot)}';
}

/// 百分比：保留一位小数。
String formatPercent(num? value) {
  if (value == null) {
    return '--';
  }
  return '${value.toStringAsFixed(1)}%';
}

/// 时长：分钟 → `7 小时 9 分`；null 返回 `—`（未采集，不按 0 展示）。
String formatDuration(int? minutes) {
  if (minutes == null || minutes < 0) {
    return '—';
  }
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (hours == 0) {
    return '$rest 分';
  }
  if (rest == 0) {
    return '$hours 小时';
  }
  return '$hours 小时 $rest 分';
}

/// 一位小数数值（千分位）：如 `4,881.2`；null 返回 `—`。
String formatOneDecimal(num? value) {
  if (value == null) {
    return '—';
  }
  final String fixed = value.abs().toStringAsFixed(1);
  final int dot = fixed.indexOf('.');
  final String sign = value < 0 ? '-' : '';
  return '$sign${_group(fixed.substring(0, dot))}${fixed.substring(dot)}';
}
