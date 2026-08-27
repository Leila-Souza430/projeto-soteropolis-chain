import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Base type for every error the FastAPI backend can hand back, already
/// classified so screens react to a specific case instead of re-parsing a
/// DioException/status code themselves.
sealed class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// The request never got a definitive answer (timeout, no connectivity, DNS,
/// connection reset). Callers must NOT clear a stored idempotency key on
/// this - the server may have received and processed the request anyway.
class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'Falha de conexão. Tente novamente.',
  ]);
}

/// 401: the Supabase session is missing or no longer valid.
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Sessão expirada.']);
}

/// 400 "User has no linked wallet_address" specifically - distinguished from
/// other 400s because it has a known fix (re-run the login flow, which
/// re-links the Carteira Digital), not a generic error banner.
class NoWalletLinkedException extends ApiException {
  const NoWalletLinkedException()
    : super('Carteira Digital ainda não vinculada. Faça login novamente.');
}

/// Any other 400. Per SPEC these "shouldn't normally be reachable by a
/// correctly-behaving app" (missing header, malformed request) - surfaced
/// with the server's own message since it signals a client-side bug rather
/// than a user-actionable state.
class BadRequestException extends ApiException {
  const BadRequestException(super.message);
}

/// 404: the referenced resource (e.g. an ecoponto_id) doesn't exist.
class NotFoundException extends ApiException {
  const NotFoundException([super.message = 'Recurso não encontrado.']);
}

/// 422 on POST /descartes, geofencing shape: `detail` is an OBJECT
/// ({message, descarte_id, distancia_metros, tolerancia_metros}). See
/// [ValidationException] for the other possible 422 shape.
class GeofenceRejectedException extends ApiException {
  final String descarteId;
  final double distanciaMetros;
  final double toleranciaMetros;

  GeofenceRejectedException({
    required this.descarteId,
    required this.distanciaMetros,
    required this.toleranciaMetros,
  }) : super(
         'Você está a ${distanciaMetros.round()}m do Ecoponto — '
         'aproxime-se até ${toleranciaMetros.round()}m e tente novamente.',
       );
}

/// 422 where `detail` is a LIST - FastAPI's own request-validation shape
/// (malformed body reaching the server), as opposed to the geofencing
/// object shape above. The two are told apart by `detail is Map` vs
/// `detail is List` in [ApiClient._mapError], never assumed.
class ValidationException extends ApiException {
  const ValidationException([
    super.message = 'Dados inválidos enviados pelo aplicativo.',
  ]);
}

/// Anything else (500 and unmapped statuses).
class UnknownApiException extends ApiException {
  const UnknownApiException([
    super.message = 'Algo deu errado. Tente novamente.',
  ]);
}

/// dio wrapper for the FastAPI backend.
///
/// Attaches the Supabase bearer token to every request via an interceptor
/// (harmless on the one unauthenticated route, GET /ecopontos - the backend
/// simply doesn't check for it there) and maps every error response into a
/// typed [ApiException] so call sites never touch a raw DioException or
/// status code.
class ApiClient {
  ApiClient({void Function()? onUnauthorized})
    : _onUnauthorized = onUnauthorized {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token =
              Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final void Function()? _onUnauthorized;

  Future<Response<T>> get<T>(String path) => _run(() => _dio.get<T>(path));

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) => _run(
    () => _dio.post<T>(
      path,
      data: data,
      options: Options(headers: headers),
    ),
  );

  Future<Response<T>> patch<T>(String path, {Object? data}) =>
      _run(() => _dio.patch<T>(path, data: data));

  Future<Response<T>> _run<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException error) {
    // badResponse is the only case with a real HTTP status code to branch
    // on below; every other DioExceptionType (timeouts, no connectivity,
    // cancellation, and any type dio adds in a future version) means the
    // request never got a definitive answer from the server.
    if (error.type != DioExceptionType.badResponse) {
      return const NetworkException();
    }

    final statusCode = error.response?.statusCode;
    final rawData = error.response?.data;
    final detail = rawData is Map ? rawData['detail'] : null;

    switch (statusCode) {
      case 401:
        // Session expired/invalid: force the app back to the login screen
        // rather than surface this inline - there is no in-place recovery.
        _onUnauthorized?.call();
        return const UnauthorizedException();
      case 400:
        if (detail == 'User has no linked wallet_address') {
          return const NoWalletLinkedException();
        }
        return BadRequestException(
          detail is String ? detail : 'Requisição inválida.',
        );
      case 404:
        return const NotFoundException();
      case 422:
        if (detail is Map) {
          return GeofenceRejectedException(
            descarteId: detail['descarte_id'] as String,
            distanciaMetros: (detail['distancia_metros'] as num).toDouble(),
            toleranciaMetros: (detail['tolerancia_metros'] as num).toDouble(),
          );
        }
        // Otherwise `detail` is a List (FastAPI validation errors).
        return const ValidationException();
      default:
        return const UnknownApiException();
    }
  }
}
