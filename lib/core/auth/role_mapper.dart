String normalizeBusinessRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'owner':
      return 'owner';
    case 'admin':
    case 'administrador':
      return 'admin';
    case 'manager':
    case 'supervisor':
      return 'manager';
    case 'cashier':
    case 'cajero':
      return 'cashier';
    case 'waiter':
    case 'mesero':
      return 'waiter';
    case 'cook':
    case 'chef':
    case 'cocina':
    case 'kitchen':
      return 'cook';
    case 'delivery':
      return 'delivery';
    default:
      return 'waiter';
  }
}

bool isAdminDashboardRole(String? role) {
  final normalized = normalizeBusinessRole(role);
  return normalized == 'owner' || normalized == 'admin';
}
