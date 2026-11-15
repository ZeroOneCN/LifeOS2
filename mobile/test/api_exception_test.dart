import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/core/network/api_exception.dart';

/// 构造一个带响应体的 DioException，用于验证错误信息提取。
ApiException badResponseOf(int statusCode, dynamic data) {
  final RequestOptions options = RequestOptions(path: '/finance/repayments');
  return ApiException.fromDio(
    DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: statusCode,
        data: data,
      ),
    ),
  );
}

void main() {
  group('ApiException 错误信息提取', () {
    test('字符串 detail 直接透出', () {
      final ApiException error = badResponseOf(400, <String, dynamic>{
        'detail': '本次应付不能超过剩余欠款',
      });
      expect(error.message, '本次应付不能超过剩余欠款');
    });

    test('422 数组型 detail 取首条并带出字段名', () {
      final ApiException error = badResponseOf(422, <String, dynamic>{
        'detail': <dynamic>[
          <String, dynamic>{
            'type': 'missing',
            'loc': <dynamic>['body', 'payable'],
            'msg': 'Field required',
          },
        ],
      });
      expect(error.statusCode, 422);
      expect(error.message, contains('payable'));
      expect(error.message, isNot('请求失败，请稍后重试'));
    });

    test('无法解析的 detail 仍回退默认文案', () {
      final ApiException error = badResponseOf(422, <String, dynamic>{
        'detail': <dynamic>[],
      });
      expect(error.message, '请求失败，请稍后重试');
    });
  });
}
