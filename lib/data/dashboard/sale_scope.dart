/// Regla única de «venta» del dashboard (2026-11-10).
///
/// Una venta es un COBRO, no el cierre de la mesa: una subcuenta pagada cuenta
/// en el momento en que se paga aunque la mesa siga abierta con otra subcuenta
/// pendiente. Así Inicio, Ventas y los reportes cuadran con la caja y con los
/// comprobantes del POS (cada subcuenta lleva el suyo).
///
///  * Dinero: pagos no anulados ni cancelados, neto del vuelto, hechos en el
///    período (payments.created_at), de una orden no anulada. El día de la
///    venta es el día del cobro.
///  * Productos e impuestos: cada línea cuenta una sola vez, en el momento en
///    que se vendió ([itemSoldAt]).
library;

/// Momento en que se vendió una línea de `order_items`: cuando se pagó su
/// subcuenta (si está en una cerrada) o, si no, cuando se cerró la orden.
/// null = no se ha vendido (mesa abierta sin pagar esa línea) o está anulada.
///
/// [item] trae `status`, `order_checks` (is_closed, closed_at) y `orders`
/// (status_ext, closed_at), embebidos.
DateTime? itemSoldAt(Map<String, dynamic> item) {
  if (item['status']?.toString() == 'void') return null;
  final order = item['orders'];
  if (order is! Map) return null;
  if (order['status_ext']?.toString() == 'void') return null;
  final check = item['order_checks'];
  if (check is Map && check['is_closed'] == true) {
    final paidAt = DateTime.tryParse(check['closed_at']?.toString() ?? '');
    if (paidAt != null) return paidAt;
  }
  return DateTime.tryParse(order['closed_at']?.toString() ?? '');
}

/// ¿La línea se vendió dentro de [start, end)?
bool itemSoldInRange(Map<String, dynamic> item, DateTime start, DateTime end) {
  final soldAt = itemSoldAt(item);
  return soldAt != null && !soldAt.isBefore(start) && soldAt.isBefore(end);
}
