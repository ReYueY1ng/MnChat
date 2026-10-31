// AppFailure / classifyDio 的分类测试。
//
// 用真实 DioException 的 type 枚举构造（不 mock），断言落到哪个变体、
// summary 非空，以及 HTTP 状态码被保留。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/app_failure.dart';

DioException _dio(
  DioExceptionType type, {
  int? statusCode,
  String? statusMessage,
}) {
  final options = RequestOptions(path: '/miniw/x');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: statusCode,
            statusMessage: statusMessage,
          ),
  );
}

void main() {
  group('classifyDio', () {
    for (final type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
    ]) {
      test('${type.name} → timeout', () {
        final failure = classifyDio(_dio(type));
        expect(failure, isA<TimeoutFailure>());
        expect(failure.summary, isNotEmpty);
      });
    }

    for (final type in <DioExceptionType>[
      DioExceptionType.connectionError,
      DioExceptionType.unknown,
      DioExceptionType.badCertificate,
    ]) {
      test('${type.name} → network', () {
        final failure = classifyDio(_dio(type));
        expect(failure, isA<NetworkFailure>());
        expect(failure.summary, isNotEmpty);
      });
    }

    test('badResponse → httpStatus 且保留状态码', () {
      final failure = classifyDio(
        _dio(
          DioExceptionType.badResponse,
          statusCode: 503,
          statusMessage: 'Service Unavailable',
        ),
      );

      expect(failure, isA<HttpStatusFailure>());
      final http = failure as HttpStatusFailure;
      expect(http.status, 503);
      expect(http.summary, contains('503'));
      expect(http.summary, isNotEmpty);
    });

    test('badResponse 缺 response 时状态码为 0，summary 仍非空', () {
      final failure = classifyDio(_dio(DioExceptionType.badResponse));
      expect(failure, isA<HttpStatusFailure>());
      expect((failure as HttpStatusFailure).status, 0);
      expect(failure.summary, isNotEmpty);
    });

    test('cancel → local(已取消)', () {
      final failure = classifyDio(_dio(DioExceptionType.cancel));
      expect(failure, isA<LocalFailure>());
      expect(failure.summary, '已取消');
    });
  });

  group('AppFailure.summary', () {
    test('所有变体都给出非空摘要', () {
      final all = <AppFailure>[
        const AppFailure.network(),
        const AppFailure.timeout(),
        const AppFailure.httpStatus(404),
        const AppFailure.httpStatus(500, detail: 'boom'),
        const AppFailure.protocol('bad lua table'),
        const AppFailure.protocol(''),
        const AppFailure.business(9, null),
        const AppFailure.business(23, '排队中'),
        const AppFailure.local('已取消'),
        const AppFailure.local(''),
      ];
      for (final f in all) {
        expect(f.summary, isNotEmpty, reason: '$f');
      }
    });

    test('httpStatus 摘要携带状态码与 detail', () {
      expect(const AppFailure.httpStatus(404).summary, contains('404'));
      expect(
        const AppFailure.httpStatus(502, detail: 'Bad Gateway').summary,
        contains('Bad Gateway'),
      );
    });

    test('business 摘要携带码与文案', () {
      expect(const AppFailure.business(9, null).summary, contains('9'));
      expect(
        const AppFailure.business(9, 'NO_ROUTE').summary,
        contains('NO_ROUTE'),
      );
    });
  });
}
