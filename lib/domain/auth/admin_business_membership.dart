import 'package:flutter/foundation.dart';

@immutable
class AdminBusinessMembership {
  const AdminBusinessMembership({
    required this.businessId,
    required this.rawRole,
    required this.normalizedRole,
    required this.businessName,
    required this.branchName,
    required this.allowed,
  });

  final String businessId;
  final String rawRole;
  final String normalizedRole;
  final String? businessName;
  final String? branchName;
  final bool allowed;
}
