import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A previously-started, not-yet-terminally-resolved request: the
/// Idempotency-Key it was (or will be) sent with, and its exact payload.
class PendingRequest {
  final String idempotencyKey;
  final Map<String, dynamic> payload;

  const PendingRequest({required this.idempotencyKey, required this.payload});
}

/// Client-side idempotency for POST /descartes and POST /resgates.
///
/// Both endpoints mint or burn real tokens server-side, so a duplicate
/// request (double-tap, retry after a dropped connection, the app getting
/// killed mid-request) must never be charged twice. The contract: generate a
/// UUID v4 and persist {key, payload} to disk BEFORE the network call fires,
/// so the key survives an app kill. Clear it only on a DEFINITIVE terminal
/// result - a 201 success, or a non-retryable 400/404/422 (the server has
/// permanently rejected this exact payload; retrying would just repeat the
/// same rejection). On a network/timeout error the outcome is unknown - the
/// request may have already reached the server - so the key is KEPT and the
/// next attempt reuses it, letting the server's own idempotency-key lookup
/// (routers/descartes.py, routers/resgates.py) replay the original result
/// instead of minting/burning a second time.
///
/// One flow name per endpoint ('descarte', 'resgate') - generalized rather
/// than hardcoded to either, per SPEC.
class IdempotencyStore {
  IdempotencyStore(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  String _keyFor(String flowName) => 'pending_idempotency_$flowName';

  /// A previously-started, still-unresolved request for [flowName], if one
  /// is on disk (meaning the last attempt never reached a terminal result).
  PendingRequest? getPending(String flowName) {
    final raw = _prefs.getString(_keyFor(flowName));
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return PendingRequest(
      idempotencyKey: decoded['idempotency_key'] as String,
      payload: decoded['payload'] as Map<String, dynamic>,
    );
  }

  /// Starts a new request: generates a fresh key, persists it with
  /// [payload] immediately, and returns it. Call once per new submission -
  /// a retry of an existing submission should reuse [getPending] instead.
  Future<PendingRequest> createPending(
    String flowName,
    Map<String, dynamic> payload,
  ) async {
    final request = PendingRequest(
      idempotencyKey: _uuid.v4(),
      payload: payload,
    );
    await _prefs.setString(
      _keyFor(flowName),
      jsonEncode({
        'idempotency_key': request.idempotencyKey,
        'payload': request.payload,
      }),
    );
    return request;
  }

  /// Clears the stored key for [flowName]. Only call after a definitive
  /// terminal result - see class doc above.
  Future<void> clearPending(String flowName) =>
      _prefs.remove(_keyFor(flowName));
}
