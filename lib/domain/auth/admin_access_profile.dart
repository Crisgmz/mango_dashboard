import 'package:flutter/foundation.dart';

import 'admin_business_membership.dart';

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

  AdminAccessProfile copyWith({
    String? businessId,
    String? businessName,
    String? branchName,
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
      businessName: businessName ?? this.businessName,
      branchName: branchName ?? this.branchName,
      rawRole: rawRole ?? this.rawRole,
      normalizedRole: normalizedRole ?? this.normalizedRole,
      allowed: allowed ?? this.allowed,
      memberships: memberships ?? this.memberships,
    );
  }
}
