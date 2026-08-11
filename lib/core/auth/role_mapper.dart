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

/// Roles que pueden entrar al dashboard. `manager` entra con UI restringida:
/// sin administración de catálogo (Productos/Ofertas), sin Suscripción y sin
/// forzar cierres de caja — ver [isOwnerOrAdminRole].
bool isAdminDashboardRole(String? role) {
  final normalized = normalizeBusinessRole(role);
  return normalized == 'owner' ||
      normalized == 'admin' ||
      normalized == 'manager';
}

/// Solo owner/admin: administración de catálogo, suscripción y acciones
/// sensibles de caja. Coincide con las políticas RLS de escritura del backend
/// (`menu_items_write`, `categories_write`…), que excluyen a manager — así la
/// UI nunca ofrece algo que la base de datos va a rechazar.
bool isOwnerOrAdminRole(String? role) {
  final normalized = normalizeBusinessRole(role);
  return normalized == 'owner' || normalized == 'admin';
}
