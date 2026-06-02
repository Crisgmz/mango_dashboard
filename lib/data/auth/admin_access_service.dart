import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/role_mapper.dart';
import '../../domain/auth/admin_access_profile.dart';
import '../../domain/auth/admin_business_membership.dart';

class AdminAccessService {
  AdminAccessService(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Future<AdminAccessProfile?> resolveCurrentAccess() async {
    final user = currentUser;
    if (user == null) return null;

    final memberships = await _loadMemberships(user.id);
    if (memberships.isEmpty) return null;

    final selected = memberships.firstWhere(
      (item) => item.allowed,
      orElse: () => memberships.first,
    );

    final profileName = await _loadProfileFullName(user.id);
    final metadata = user.userMetadata;
    final displayName = _firstNonEmpty([
          profileName,
          metadata?['full_name']?.toString(),
          metadata?['name']?.toString(),
          user.email?.split('@').first,
        ]) ??
        'Admin';

    return AdminAccessProfile(
      userId: user.id,
      userName: displayName,
      email: user.email,
      businessId: selected.businessId,
      businessName: selected.businessName,
      branchName: selected.branchName,
      rawRole: selected.rawRole,
      normalizedRole: selected.normalizedRole,
      allowed: selected.allowed,
      memberships: memberships,
    );
  }

  Future<String?> _loadProfileFullName(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      final name = row?['full_name']?.toString().trim();
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final v in values) {
      final trimmed = v?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Future<List<AdminBusinessMembership>> _loadMemberships(String userId) async {
    final memberships = await _client
        .from('user_businesses')
        .select('business_id, role, businesses(business_name, branch_name)')
        .eq('user_id', userId);

    return (memberships as List)
        .cast<dynamic>()
        .map((row) {
          final rawRole = row['role']?.toString() ?? '';
          final normalizedRole = normalizeBusinessRole(rawRole);
          final business = row['businesses'];
          return AdminBusinessMembership(
            businessId: row['business_id'] as String,
            rawRole: rawRole,
            normalizedRole: normalizedRole,
            businessName: business is Map<String, dynamic>
                ? business['business_name']?.toString()
                : null,
            branchName: business is Map<String, dynamic>
                ? business['branch_name']?.toString()
                : null,
            allowed: isAdminDashboardRole(rawRole),
          );
        })
        .toList(growable: false);
  }

  Future<AdminAccessProfile?> switchBusiness({
    required AdminAccessProfile current,
    required String businessId,
  }) async {
    final membership = current.memberships.where((item) => item.businessId == businessId).firstOrNull;
    if (membership == null) return current;

    return current.copyWith(
      businessId: membership.businessId,
      businessName: membership.businessName,
      branchName: membership.branchName,
      rawRole: membership.rawRole,
      normalizedRole: membership.normalizedRole,
      allowed: membership.allowed,
    );
  }

  String? get currentRefreshToken => _client.auth.currentSession?.refreshToken;

  /// JSON of the current session — captures access + refresh tokens, expiry,
  /// and user info. Used for instant restore via [recoverSerializedSession]
  /// without a network call when the access token is still valid.
  ///
  /// Format must match what `auth.recoverSession()` expects:
  /// `{ "currentSession": <session.toJson()>, "expiresAt": <unix-seconds> }`.
  /// Passing the session JSON directly (without the wrapper) makes
  /// `recoverSession` throw with "Missing currentSession.".
  String? get currentSerializedSession {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    try {
      return jsonEncode({
        'currentSession': session.toJson(),
        'expiresAt': session.expiresAt,
      });
    } catch (_) {
      return null;
    }
  }

  /// Expiry (UTC seconds since epoch) of the current access token, if any.
  int? get currentAccessTokenExpiresAt => _client.auth.currentSession?.expiresAt;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Restaura sesión usando un refresh token guardado.
  /// Retorna true si la sesión se restauró exitosamente.
  Future<bool> restoreSession(String refreshToken) async {
    try {
      final response = await _client.auth.setSession(refreshToken);
      return response.session != null;
    } catch (_) {
      return false;
    }
  }

  /// Restores a previously serialized session JSON without a network round-trip
  /// when the access token is still valid. Returns true on success.
  ///
  /// Pre-valida el JSON antes de llamar a `recoverSession` porque cuando le
  /// pasamos basura, el SDK emite el error tanto por excepción (que sí
  /// atrapamos) como por su stream `onAuthStateChange`, donde puede aterrizar
  /// como uncaught exception. Validar arriba elimina ese segundo camino.
  Future<bool> recoverSerializedSession(String serializedJson) async {
    if (!_looksLikeValidSession(serializedJson)) return false;
    try {
      final response = await _client.auth.recoverSession(serializedJson);
      final session = response.session;
      if (session == null) return false;
      // If the recovered access token is still valid, no network was needed.
      // The Supabase SDK will lazily refresh on next API call if expired.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sanity-check: ¿este string parece un Session JSON serializado válido?
  /// Lo que necesita Supabase: access_token, refresh_token, expires_in y
  /// un objeto user con id. Si falta alguno, no llamamos al SDK.
  bool _looksLikeValidSession(String serializedJson) {
    try {
      final data = jsonDecode(serializedJson);
      if (data is! Map<String, dynamic>) return false;
      final accessToken = data['access_token'];
      final refreshToken = data['refresh_token'];
      final user = data['user'];
      if (accessToken is! String || accessToken.isEmpty) return false;
      if (refreshToken is! String || refreshToken.isEmpty) return false;
      if (user is! Map<String, dynamic>) return false;
      if (user['id'] is! String) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> authStates() => _client.auth.onAuthStateChange;
}
