import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/domain/purchasing/purchase_order.dart';

/// Detalle de OC: cabecera y líneas llegan en lecturas separadas
/// (`loadPurchaseOrderDetail`) y se unen bajo `purchase_order_items`.
void main() {
  Map<String, dynamic> line({String? description, Object? item}) => {
    'id': 'l1',
    'inventory_item_id': 'i1',
    'description': description,
    'quantity_ordered': 5,
    'quantity_received': '2',
    'unit_cost': 120.5,
    'tax_rate': 18,
    'total': 602.5,
    'inventory_items': item,
  };

  test('usa la descripción de la línea si existe', () {
    final l = PurchaseOrderLine.fromJson(
        line(description: 'Queso', item: {'name': 'Queso mozzarella', 'unit': 'kg'}));
    expect(l.description, 'Queso');
    expect(l.unit, 'kg');
    expect(l.quantityReceived, 2);
  });

  test('sin descripción cae al nombre del insumo', () {
    final l = PurchaseOrderLine.fromJson(
        line(description: '  ', item: {'name': 'Harina', 'unit': ''}));
    expect(l.description, 'Harina');
    expect(l.unit, isNull);
  });

  test('sin descripción ni insumo muestra Ítem', () {
    expect(PurchaseOrderLine.fromJson(line()).description, 'Ítem');
  });

  test('la orden toma las líneas unidas a la cabecera', () {
    final order = PurchaseOrder.fromJson({
      'id': 'po1',
      'order_number': 'PO-00007',
      'status': 'sent',
      'total': 710.95,
      'suppliers': {'name': 'Distribuidora Sol', 'whatsapp': null, 'phone': '8095550000'},
      'purchase_order_items': [line(description: 'Queso')],
    });
    expect(order.supplierName, 'Distribuidora Sol');
    expect(order.lines, hasLength(1));
    expect(order.lines.single.total, 602.5);
  });
}
