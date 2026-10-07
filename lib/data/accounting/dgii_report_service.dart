import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/accounting/dgii_catalogs.dart';
import '../../domain/accounting/dgii_reports.dart';

/// Se lanza cuando la tabla que alimenta un formato todavía no existe en el
/// backend (migración sin aplicar). La vista lo distingue de un error de red
/// para poder decir exactamente qué falta.
class DgiiSourceUnavailable implements Exception {
  const DgiiSourceUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Arma los formatos de envío 606, 607 y 608 de la DGII desde lo que el POS ya
/// registró. No inventa nada: cada columna sale de una columna real.
///
/// A diferencia del resto de los reportes de ventas —anclados en
/// `orders.closed_at`— estos van por **fecha del comprobante**
/// (`fiscal_documents.issued_at`, `purchase_receptions.document_date`), que es
/// lo que la DGII declara. Por eso no reusan el scope canónico de ventas.
class DgiiReportService {
  DgiiReportService(this._client);

  final SupabaseClient _client;
  static const _batchSize = 40;
  static const _pageSize = 1000;

  /// RNC y razón social del negocio: van en la cabecera de los tres archivos.
  Future<({String? rnc, String? legalName})> businessTaxpayer(
      String businessId) async {
    try {
      final row = await _client
          .from('fiscal_settings')
          .select('rnc, business_legal_name')
          .eq('business_id', businessId)
          .maybeSingle();
      if (row == null) return (rnc: null, legalName: null);
      return (
        rnc: _text(row['rnc']),
        legalName: _text(row['business_legal_name']),
      );
    } catch (_) {
      // Sin configuración fiscal el archivo se genera igual; la vista avisa que
      // hay que completar el RNC antes de subirlo al prevalidador.
      return (rnc: null, legalName: null);
    }
  }

  // ── 606 · Compras de bienes y servicios ───────────────────────────────────

  /// Recepciones de mercancía del período. `purchase_receptions` nació con el
  /// bloque fiscal del 606 (migración 20260811_0002), así que los montos,
  /// retenciones y la forma de pago ya vienen capturados.
  ///
  /// Se filtra por `document_date` (la fecha del NCF del proveedor) y se cae a
  /// `reception_date` solo cuando la recepción no registró fecha de documento.
  Future<List<Dgii606Row>> load606({
    required String businessId,
    required DgiiPeriod period,
  }) async {
    final startIso = _dateOnly(period.start);
    final endIso = _dateOnly(period.end);
    const cols = 'id, supplier_id, ncf, ncf_type, ncf_modified, document_date, '
        'payment_date, reception_date, goods_amount, services_amount, '
        'itbis_invoiced, itbis_withheld, isr_withheld, isc, legal_tip, '
        'payment_method, status';

    List<Map<String, dynamic>> rows;
    var withSupplier = true;
    try {
      rows = await _paginate((from, to) => _client
          .from('purchase_receptions')
          .select('$cols, suppliers(name, rnc, tax_id_type)')
          .eq('business_id', businessId)
          .neq('status', 'cancelled')
          .or('and(document_date.gte.$startIso,document_date.lt.$endIso),'
              'and(document_date.is.null,reception_date.gte.$startIso,'
              'reception_date.lt.$endIso)')
          .order('document_date', ascending: true)
          .range(from, to));
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        throw const DgiiSourceUnavailable(
          'El 606 se arma con las recepciones de compra, y esa parte del '
          'backend todavía no está instalada en este servidor.',
        );
      }
      if (e.code != '42703') rethrow;
      // `suppliers.tax_id_type` llega con la migración 20260811_0001. Sin ella
      // el tipo de identificación se deduce por la forma del número.
      withSupplier = false;
      rows = await _paginate((from, to) => _client
          .from('purchase_receptions')
          .select('$cols, suppliers(name, rnc)')
          .eq('business_id', businessId)
          .neq('status', 'cancelled')
          .or('and(document_date.gte.$startIso,document_date.lt.$endIso),'
              'and(document_date.is.null,reception_date.gte.$startIso,'
              'reception_date.lt.$endIso)')
          .order('document_date', ascending: true)
          .range(from, to));
    }

    return rows.map((row) {
      final supplier = row['suppliers'];
      final s = supplier is Map ? Map<String, dynamic>.from(supplier) : const {};
      final taxId = _digitsOrText(s['rnc']);
      return Dgii606Row(
        receptionId: row['id'].toString(),
        supplierId: _text(row['supplier_id']),
        supplierName: _text(s['name']) ?? 'Proveedor sin nombre',
        taxId: taxId,
        idType: dgiiIdTypeFor(
          taxId,
          declaredType: withSupplier ? _text(s['tax_id_type']) : null,
        ),
        ncf: _text(row['ncf']),
        ncfModified: _text(row['ncf_modified']),
        documentDate: _date(row['document_date']) ?? _date(row['reception_date']),
        paymentDate: _date(row['payment_date']),
        servicesAmount: _num(row['services_amount']),
        goodsAmount: _num(row['goods_amount']),
        itbisInvoiced: _num(row['itbis_invoiced']),
        itbisWithheld: _num(row['itbis_withheld']),
        isrWithheld: _num(row['isr_withheld']),
        isc: _num(row['isc']),
        legalTip: _num(row['legal_tip']),
        paymentForm: dgiiPurchasePaymentForm(_text(row['payment_method'])),
      );
    }).toList(growable: false);
  }

  // ── 607 · Ventas de bienes y servicios ────────────────────────────────────

  /// Comprobantes emitidos en el período, con el desglose por forma de cobro.
  ///
  /// El desglose sale de `payments`: se agrupa por división (`check_id`) cuando
  /// el comprobante se emitió por una, y por pedido cuando cubre el pedido
  /// completo. Así una factura de una mesa dividida no se lleva los cobros de
  /// las otras divisiones.
  Future<List<Dgii607Row>> load607({
    required String businessId,
    required DgiiPeriod period,
  }) async {
    final startIso = period.start.toUtc().toIso8601String();
    final endIso = period.end.toUtc().toIso8601String();

    final docs = await _paginate((from, to) => _client
        .from('fiscal_documents')
        .select('id, order_id, check_id, ncf_type, ncf_number, customer_rnc, '
            'customer_name, subtotal, itbis_amount, service_fee, total, '
            'issued_at, related_document_id')
        .eq('business_id', businessId)
        .neq('status', 'cancelled')
        .gte('issued_at', startIso)
        .lt('issued_at', endIso)
        .order('issued_at', ascending: true)
        .range(from, to));
    if (docs.isEmpty) return const [];

    final orderIds = <String>{};
    final relatedIds = <String>{};
    for (final d in docs) {
      final orderId = _text(d['order_id']);
      if (orderId != null) orderIds.add(orderId);
      final related = _text(d['related_document_id']);
      if (related != null) relatedIds.add(related);
    }

    // Se lanzan las dos juntas y se esperan por separado: `Future.wait` con
    // tipos distintos colapsaría el tipo estático de los resultados.
    final paymentsFuture = _paymentsByScope(orderIds.toList(growable: false));
    final relatedFuture = _ncfByDocumentId(relatedIds.toList(growable: false));
    final payments = await paymentsFuture;
    final relatedNcf = await relatedFuture;

    return docs.map((d) {
      final checkId = _text(d['check_id']);
      final orderId = _text(d['order_id']);
      // Un comprobante por división cobra contra la división; si no hay
      // división, contra el pedido completo.
      final split = (checkId != null ? payments['check:$checkId'] : null) ??
          (orderId != null ? payments['order:$orderId'] : null) ??
          const _PaymentSplit();
      final taxId = _digitsOrText(d['customer_rnc']);
      return Dgii607Row(
        documentId: d['id'].toString(),
        taxId: taxId,
        idType: dgiiIdTypeFor(taxId),
        ncf: _text(d['ncf_number']) ?? '',
        ncfType: _text(d['ncf_type']) ?? '',
        ncfModified: relatedNcf[_text(d['related_document_id']) ?? ''],
        customerName: _text(d['customer_name']),
        issuedAt: _date(d['issued_at']) ?? period.start,
        amountInvoiced: _num(d['subtotal']),
        itbisInvoiced: _num(d['itbis_amount']),
        legalTip: _num(d['service_fee']),
        cash: split.cash,
        transfer: split.transfer,
        card: split.card,
        credit: split.credit,
        other: split.other,
      );
    }).toList(growable: false);
  }

  // ── 608 · Comprobantes anulados ───────────────────────────────────────────

  /// Comprobantes anulados en el período. Se filtra por `cancelled_at`, y se
  /// cae a `issued_at` para los anulados viejos que no lo registraron.
  Future<List<Dgii608Row>> load608({
    required String businessId,
    required DgiiPeriod period,
  }) async {
    final startIso = period.start.toUtc().toIso8601String();
    final endIso = period.end.toUtc().toIso8601String();

    final rows = await _paginate((from, to) => _client
        .from('fiscal_documents')
        .select('id, ncf_type, ncf_number, total, issued_at, cancelled_at, '
            'cancellation_reason')
        .eq('business_id', businessId)
        .eq('status', 'cancelled')
        .or('and(cancelled_at.gte.$startIso,cancelled_at.lt.$endIso),'
            'and(cancelled_at.is.null,issued_at.gte.$startIso,'
            'issued_at.lt.$endIso)')
        .order('issued_at', ascending: true)
        .range(from, to));

    return rows.map((row) {
      final reason = _text(row['cancellation_reason']);
      return Dgii608Row(
        documentId: row['id'].toString(),
        ncf: _text(row['ncf_number']) ?? '',
        ncfType: _text(row['ncf_type']) ?? '',
        documentDate: _date(row['issued_at']) ?? period.start,
        cancelledAt: _date(row['cancelled_at']),
        total: _num(row['total']),
        reason: reason,
        suggestedVoidCode: dgiiVoidReasonFrom(reason),
      );
    }).toList(growable: false);
  }

  // ── Internos ──────────────────────────────────────────────────────────────

  /// Cobros completados de los pedidos dados, agrupados por `check:<id>` y
  /// `order:<id>`. Un cobro de una división cuenta en las dos llaves: contra su
  /// división y contra el pedido, para que un comprobante del pedido completo
  /// vea todo lo cobrado.
  Future<Map<String, _PaymentSplit>> _paymentsByScope(
      List<String> orderIds) async {
    if (orderIds.isEmpty) return {};
    final rows = await _batchedInFilter(
      table: 'payments',
      select: 'order_id, check_id, amount, change_amount, status, '
          'payment_methods(code)',
      filterColumn: 'order_id',
      values: orderIds,
    );

    final out = <String, _PaymentSplit>{};
    for (final row in rows) {
      if (_text(row['status']) != 'completed') continue;
      final pm = row['payment_methods'];
      final code = pm is Map ? _text(pm['code']) : null;
      // Neto de vuelto: lo que de verdad entró por ese método.
      final net = _num(row['amount']) - _num(row['change_amount']);
      if (net == 0) continue;

      final orderId = _text(row['order_id']);
      final checkId = _text(row['check_id']);
      for (final key in [
        if (checkId != null) 'check:$checkId',
        if (orderId != null) 'order:$orderId',
      ]) {
        out[key] = (out[key] ?? const _PaymentSplit()).plus(code, net);
      }
    }
    return out;
  }

  /// `fiscal_document.id -> ncf_number`, para resolver el NCF modificado que
  /// las notas de crédito/débito guardan por id.
  Future<Map<String, String>> _ncfByDocumentId(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _batchedInFilter(
      table: 'fiscal_documents',
      select: 'id, ncf_number',
      filterColumn: 'id',
      values: ids,
    );
    final out = <String, String>{};
    for (final row in rows) {
      final ncf = _text(row['ncf_number']);
      if (ncf != null) out[row['id'].toString()] = ncf;
    }
    return out;
  }

  /// `.inFilter()` por lotes: un IN con cientos de uuid revienta el límite de
  /// largo de la URI. Mismo patrón que `DashboardDataService`.
  Future<List<Map<String, dynamic>>> _batchedInFilter({
    required String table,
    required String select,
    required String filterColumn,
    required List<String> values,
  }) async {
    if (values.isEmpty) return [];
    final futures = <Future<List<dynamic>>>[];
    for (var i = 0; i < values.length; i += _batchSize) {
      final end = i + _batchSize > values.length ? values.length : i + _batchSize;
      futures.add(_client
          .from(table)
          .select(select)
          .inFilter(filterColumn, values.sublist(i, end)));
    }
    final batches = await Future.wait(futures);
    final results = <Map<String, dynamic>>[];
    for (final batch in batches) {
      results.addAll(List<Map<String, dynamic>>.from(batch));
    }
    return results;
  }

  /// Recorre todas las páginas de una consulta (PostgREST corta en ~1000
  /// filas). Un mes de ventas de consumo pasa ese tope sin esfuerzo.
  Future<List<Map<String, dynamic>>> _paginate(
    Future<dynamic> Function(int from, int to) page,
  ) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final res = await page(from, from + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(res as List);
      all.addAll(list);
      if (list.length < _pageSize) break;
      from += _pageSize;
    }
    return all;
  }
}

/// Desglose de cobro de un comprobante por forma de venta del 607.
class _PaymentSplit {
  const _PaymentSplit({
    this.cash = 0,
    this.transfer = 0,
    this.card = 0,
    this.credit = 0,
    this.other = 0,
  });

  final double cash;
  final double transfer;
  final double card;
  final double credit;
  final double other;

  _PaymentSplit plus(String? methodCode, double amount) {
    switch (methodCode) {
      case 'cash':
        return _copy(cash: cash + amount);
      case 'transfer':
        return _copy(transfer: transfer + amount);
      case 'card':
        return _copy(card: card + amount);
      case 'credit':
        return _copy(credit: credit + amount);
      default:
        // Métodos propios del negocio (puntos, cortesía, gift card…): la DGII
        // los agrupa en "otras formas de venta".
        return _copy(other: other + amount);
    }
  }

  _PaymentSplit _copy({
    double? cash,
    double? transfer,
    double? card,
    double? credit,
    double? other,
  }) =>
      _PaymentSplit(
        cash: cash ?? this.cash,
        transfer: transfer ?? this.transfer,
        card: card ?? this.card,
        credit: credit ?? this.credit,
        other: other ?? this.other,
      );
}

String? _text(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Identificación fiscal: deja solo dígitos cuando los hay (RNC y cédula
/// vienen escritos con guiones), y respeta el texto tal cual cuando es un
/// pasaporte.
String? _digitsOrText(dynamic value) {
  final raw = _text(value);
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? raw : digits;
}

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// `AAAA-MM-DD` para comparar contra columnas `date` de Postgres.
String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime? _date(dynamic value) {
  final raw = _text(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
