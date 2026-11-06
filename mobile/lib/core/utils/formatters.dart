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
