import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/purchasing/purchasing_data_service.dart';
import '../../../domain/purchasing/purchase_order.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/purchase_orders_view_model.dart';
import 'purchase_orders_view.dart' show statusColor;
import 'reception_view.dart';

/// Detalle de una orden de compra: líneas con progreso de recepción, totales
/// y acciones según estado (enviar por WhatsApp, marcar enviada, cancelar).
class PurchaseOrderDetailView extends ConsumerStatefulWidget {
  const PurchaseOrderDetailView({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PurchaseOrderDetailView> createState() =>
      _PurchaseOrderDetailViewState();
}

class _PurchaseOrderDetailViewState
    extends ConsumerState<PurchaseOrderDetailView> {
  late Future<PurchaseOrder> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PurchaseOrder> _load() =>
      ref.read(purchasingDataServiceProvider).loadPurchaseOrderDetail(widget.orderId);

  void _reload() => setState(() => _future = _load());

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Normaliza a formato wa.me: solo dígitos y con código de país (RD = 1).
  String? _waPhone(PurchaseOrder order) {
    final raw = order.supplierWhatsapp?.trim().isNotEmpty == true
        ? order.supplierWhatsapp!
        : (order.supplierPhone ?? '');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (digits.length == 10) return '1$digits';
    return digits;
  }

  String _waMessage(PurchaseOrder order) {
    final business =
        ref.read(authGateViewModelProvider).profile?.businessName ?? 'MangoPOS';
    final buffer = StringBuffer()
      ..writeln('*Orden de compra ${order.orderNumber}*')
      ..writeln(business)
      ..writeln();
    if (order.expectedDate != null) {
      buffer.writeln(
          'Entrega esperada: ${MangoFormatters.date(order.expectedDate!)}');
      buffer.writeln();
    }
    for (final l in order.lines) {
      buffer.writeln(
          '• ${MangoFormatters.number(l.quantityOrdered)} × ${l.description} — ${MangoFormatters.currency(l.unitCost)} c/u');
    }
    buffer
      ..writeln()
      ..writeln('Subtotal: ${MangoFormatters.currency(order.subtotal)}')
      ..writeln('ITBIS: ${MangoFormatters.currency(order.tax)}')
      ..writeln('*Total: ${MangoFormatters.currency(order.total)}*');
    if (order.notes != null && order.notes!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Notas: ${order.notes!.trim()}');
    }
    return buffer.toString();
  }

  Future<void> _sendWhatsApp(PurchaseOrder order) async {
    final phone = _waPhone(order);
    if (phone == null) {
      _snack('El suplidor no tiene WhatsApp ni teléfono registrado.');
      return;
    }
    final uri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(_waMessage(order))}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      _snack('No se pudo abrir WhatsApp.');
      return;
    }
    // Si aún estaba en borrador, al enviarla por WhatsApp pasa a 'sent'.
    if (order.isDraft) {
      final businessId = _businessId;
      if (businessId != null) {
        await ref
            .read(purchaseOrdersViewModelProvider.notifier)
            .markSent(businessId, order.id);
        _reload();
      }
    }
  }

  Future<void> _markSent(PurchaseOrder order) async {
    final businessId = _businessId;
    if (businessId == null) return;
    final ok = await ref
        .read(purchaseOrdersViewModelProvider.notifier)
        .markSent(businessId, order.id);
    if (!mounted) return;
    if (ok) {
      _reload();
    } else {
      _snack(ref.read(purchaseOrdersViewModelProvider).error ??
          'No se pudo actualizar la orden.');
    }
  }

  Future<void> _cancel(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar orden'),
        content: Text('¿Cancelar la orden ${order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: MangoThemeFactory.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final businessId = _businessId;
    if (businessId == null) return;
    final ok = await ref
        .read(purchaseOrdersViewModelProvider.notifier)
        .cancel(businessId, order.id);
    if (!mounted) return;
    if (ok) {
      _reload();
    } else {
      _snack(ref.read(purchaseOrdersViewModelProvider).error ??
          'No se pudo cancelar la orden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Orden de compra')),
      body: FutureBuilder<PurchaseOrder>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _LoadError(error: snapshot.error, onRetry: _reload);
          }
          final order = snapshot.data!;
          final color = statusColor(order.status);
          final orderedQty = order.lines
              .fold<double>(0, (sum, l) => sum + l.quantityOrdered);
          final receivedQty = order.lines
              .fold<double>(0, (sum, l) => sum + l.quantityReceived);
          final progress =
              orderedQty > 0 ? (receivedQty / orderedQty).clamp(0.0, 1.0) : 0.0;

          return ListView(
            padding: EdgeInsets.all(dpi.space(16)),
            children: [
              // ── Hero de la orden ──
              Container(
                padding: EdgeInsets.all(dpi.space(16)),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(dpi.radius(18)),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: dpi.scale(44),
                          height: dpi.scale(44),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(dpi.radius(12)),
                          ),
                          child: Icon(Icons.receipt_long_rounded,
                              color: color, size: dpi.icon(22)),
                        ),
                        SizedBox(width: dpi.space(12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.supplierName ?? 'Sin suplidor',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: dpi.space(2)),
                              Text(
                                order.orderNumber,
                                style: TextStyle(
                                  fontSize: dpi.font(11.5),
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  color: MangoThemeFactory.mutedText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(10),
                              vertical: dpi.space(4)),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(dpi.radius(8)),
                          ),
                          child: Text(
                            order.statusLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: dpi.font(10),
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: dpi.space(14)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total de la orden',
                                  style: TextStyle(
                                      fontSize: dpi.font(10.5),
                                      color: MangoThemeFactory.mutedText(
                                          context))),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  MangoFormatters.currency(order.total),
                                  style: TextStyle(
                                    fontSize: dpi.font(22),
                                    fontWeight: FontWeight.w800,
                                    color:
                                        MangoThemeFactory.textColor(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (orderedQty > 0)
                          Text(
                            'Recibido ${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: dpi.font(11),
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                      ],
                    ),
                    if (orderedQty > 0) ...[
                      SizedBox(height: dpi.space(8)),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: dpi.scale(6),
                          backgroundColor: color.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                    SizedBox(height: dpi.space(10)),
                    Text(
                      [
                        if (order.createdAt != null)
                          'Creada ${MangoFormatters.date(order.createdAt!)}',
                        if (order.expectedDate != null)
                          'Esperada ${MangoFormatters.date(order.expectedDate!)}',
                        if (order.receivedDate != null)
                          'Recibida ${MangoFormatters.date(order.receivedDate!)}',
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context)),
                    ),
                  ],
                ),
              ),
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                SizedBox(height: dpi.space(10)),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(dpi.space(10)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.altSurface(context),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Text(order.notes!.trim(),
                      style: TextStyle(fontSize: dpi.font(12))),
                ),
              ],
              SizedBox(height: dpi.space(16)),

              Text(
                'LÍNEAS (${order.lines.length})',
                style: TextStyle(
                  fontSize: dpi.font(10),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: MangoThemeFactory.mutedText(context),
                ),
              ),
              SizedBox(height: dpi.space(8)),
              ...order.lines.map((l) {
                final received = l.quantityReceived > 0;
                final lineColor = l.fullyReceived
                    ? MangoThemeFactory.success
                    : received
                        ? MangoThemeFactory.warning
                        : MangoThemeFactory.mutedText(context);
                final lineProgress = l.quantityOrdered > 0
                    ? (l.quantityReceived / l.quantityOrdered).clamp(0.0, 1.0)
                    : 0.0;
                return Container(
                  margin: EdgeInsets.only(bottom: dpi.space(8)),
                  padding: EdgeInsets.all(dpi.space(12)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.cardColor(context),
                    borderRadius: BorderRadius.circular(dpi.radius(14)),
                    border: Border.all(
                        color: MangoThemeFactory.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: dpi.scale(30),
                            height: dpi.scale(30),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: MangoThemeFactory.mango
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              MangoFormatters.number(l.quantityOrdered),
                              style: TextStyle(
                                fontSize: dpi.font(11),
                                fontWeight: FontWeight.bold,
                                color: MangoThemeFactory.mango,
                              ),
                            ),
                          ),
                          SizedBox(width: dpi.space(10)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.description,
                                  style: TextStyle(
                                      fontSize: dpi.font(13),
                                      fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: dpi.space(2)),
                                Text(
                                  '${MangoFormatters.currency(l.unitCost)} ${l.unit != null ? 'por ${l.unit}' : 'c/u'}'
                                  '${l.taxRate > 0 ? ' · ITBIS ${l.taxRate.toStringAsFixed(0)}%' : ''}',
                                  style: TextStyle(
                                    fontSize: dpi.font(11),
                                    color:
                                        MangoThemeFactory.mutedText(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            MangoFormatters.currency(l.total),
                            style: TextStyle(
                                fontSize: dpi.font(13),
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      if (received) ...[
                        SizedBox(height: dpi.space(8)),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: lineProgress,
                                  minHeight: dpi.scale(5),
                                  backgroundColor:
                                      lineColor.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      lineColor),
                                ),
                              ),
                            ),
                            SizedBox(width: dpi.space(8)),
                            Text(
                              '${MangoFormatters.number(l.quantityReceived)}/${MangoFormatters.number(l.quantityOrdered)}',
                              style: TextStyle(
                                fontSize: dpi.font(10.5),
                                fontWeight: FontWeight.w700,
                                color: lineColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),

              SizedBox(height: dpi.space(8)),
              Container(
                padding: EdgeInsets.all(dpi.space(14)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.altSurface(context),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                ),
                child: Column(
                  children: [
                    _totalRow(context, 'Subtotal', order.subtotal),
                    SizedBox(height: dpi.space(4)),
                    _totalRow(context, 'ITBIS', order.tax),
                    Divider(color: MangoThemeFactory.borderColor(context)),
                    _totalRow(context, 'Total', order.total, bold: true),
                  ],
                ),
              ),
              SizedBox(height: dpi.space(20)),

              if (order.isOpen) ...[
                FilledButton.icon(
                  onPressed: () async {
                    final received = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => ReceptionView(order: order)),
                    );
                    if (received == true) _reload();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: MangoThemeFactory.mango,
                    padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
                  ),
                  icon: const Icon(Icons.inventory_rounded),
                  label: const Text('Recibir mercancía'),
                ),
                SizedBox(height: dpi.space(10)),
                FilledButton.icon(
                  onPressed: () => _sendWhatsApp(order),
                  style: FilledButton.styleFrom(
                    backgroundColor: MangoThemeFactory.whatsapp,
                    padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(order.isDraft
                      ? 'Enviar por WhatsApp'
                      : 'Reenviar por WhatsApp'),
                ),
                SizedBox(height: dpi.space(10)),
                if (order.isDraft)
                  OutlinedButton.icon(
                    onPressed: () => _markSent(order),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: dpi.space(13)),
                    ),
                    icon: const Icon(Icons.mark_email_read_rounded, size: 18),
                    label: const Text('Marcar como enviada (sin WhatsApp)'),
                  ),
                if (order.status == 'draft' || order.status == 'sent') ...[
                  SizedBox(height: dpi.space(10)),
                  TextButton.icon(
                    onPressed: () => _cancel(order),
                    style: TextButton.styleFrom(
                        foregroundColor: MangoThemeFactory.danger),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar orden'),
                  ),
                ],
              ],
              SizedBox(height: dpi.space(24)),
            ],
          );
        },
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, double value,
      {bool bold = false}) {
    final dpi = DpiScale.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: dpi.font(12.5),
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        Text(MangoFormatters.currency(value),
            style: TextStyle(
                fontSize: dpi.font(13),
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ],
    );
  }
}

/// Falla al abrir la orden: muestra el motivo real (RLS, red, orden borrada)
/// en vez de un texto genérico, y deja reintentar sin salir de la pantalla.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  String get _detail {
    final e = error;
    if (e is PostgrestException) return e.message;
    if (e is PurchasingException) return e.message;
    return e?.toString() ?? 'Sin respuesta del servidor.';
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: dpi.icon(42),
                color: MangoThemeFactory.mutedText(context)
                    .withValues(alpha: 0.6)),
            SizedBox(height: dpi.space(10)),
            Text('No se pudo abrir la orden',
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: dpi.space(4)),
            Text(
              _detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: dpi.space(14)),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: dpi.icon(18)),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
