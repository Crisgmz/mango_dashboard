import 'package:flutter/foundation.dart';

import 'admin_business_membership.dart';

const Object _unset = Object();

@immutable
class AdminAccessProfile {
  const AdminAccessProfile({
    required this.userId,
    required this.userName,
    required this.email,
    required this.businessId,
    required this.businessName,
    required this.branchName,
    required this.rawRole,
    required this.normalizedRole,
    required this.allowed,
    required this.memberships,
  });

  final String userId;
  final String userName;
  final String? email;
  final String businessId;
  final String? businessName;
  final String? branchName;
  final String rawRole;
  final String normalizedRole;
  final bool allowed;
  final List<AdminBusinessMembership> memberships;

  /// Returns a copy with overridden fields.
  /// Nullable fields use a sentinel so callers can explicitly clear them
  /// (passing `null`) — without it, `??` would mask the new null and keep
  /// the stale value, which caused the header to show the previous
  /// sucursal name after a branch switch.
  AdminAccessProfile copyWith({
    String? businessId,
    Object? businessName = _unset,
    Object? branchName = _unset,
    String? rawRole,
    String? normalizedRole,
    bool? allowed,
    List<AdminBusinessMembership>? memberships,
  }) {
    return AdminAccessProfile(
      userId: userId,
      userName: userName,
      email: email,
      businessId: businessId ?? this.businessId,
      businessName: identical(businessName, _unset) ? this.businessName : businessName as String?,
      branchName: identical(branchName, _unset) ? this.branchName : branchName as String?,
      rawRole: rawRole ?? this.rawRole,
      normalizedRole: normalizedRole ?? this.normalizedRole,
      allowed: allowed ?? this.allowed,
      memberships: memberships ?? this.memberships,
    );
  }
}
