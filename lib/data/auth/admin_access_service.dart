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

    final metadata = user.userMetadata;
    final displayName = metadata?['full_name']?.toString() ?? 
                       metadata?['name']?.toString() ?? 
                       user.email?.split('@').first ?? 
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

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> authStates() => _client.auth.onAuthStateChange;
}
