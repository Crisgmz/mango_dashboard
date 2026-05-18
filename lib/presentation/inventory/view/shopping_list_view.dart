import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/inventory_models.dart';
import '../../theme/theme_data_factory.dart';

/// Lista de compras: insumos con stock bajo o agotados, con cantidad
/// sugerida a comprar. El usuario puede marcar items como "comprado"
/// (estado local), copiar la lista al portapapeles o compartirla.
class ShoppingListView extends StatefulWidget {
  const ShoppingListView({super.key, required this.items});

  /// Items pre-filtrados desde el inventario (los que están en bajo o
  /// agotados). Se ordenan dentro por mayor déficit primero.
  final List<InventoryItemSnapshot> items;

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState extends State<ShoppingListView> {
  final Set<String> _purchased = {};

  late final List<InventoryItemSnapshot> _items = [...widget.items]
    ..sort((a, b) {
      // Agotados primero, luego por déficit (mín − actual) descendente.
      final aOut = a.isOut ? 1 : 0;
      final bOut = b.isOut ? 1 : 0;
      if (aOut != bOut) return bOut - aOut;
      final aDeficit = (a.minStock - a.totalQuantity).clamp(0, double.infinity);
      final bDeficit = (b.minStock - b.totalQuantity).clamp(0, double.infinity);
      return bDeficit.compareTo(aDeficit);
    });

  String _buildShareText() {
    final lines = <String>[
      'Lista de compras',
      '— ${MangoFormatters.dateTime(DateTime.now())}',
      '',
    ];
    for (final item in _items) {
      if (_purchased.contains(item.itemId)) continue;
      final qty = item.suggestedPurchase > 0 ? item.suggestedPurchase : item.minStock;
      lines.add(
        '• ${item.name}: ${MangoFormatters.number(qty.round())} ${item.unit}'
        '${item.isOut ? '  (AGOTADO)' : '  (mín ${MangoFormatters.number(item.minStock.round())})'}',
      );
    }
    final pending = _items.where((i) => !_purchased.contains(i.itemId)).length;
    lines.add('');
    lines.add('Total: $pending ${pending == 1 ? 'insumo' : 'insumos'}');
    return lines.join('\n');
  }

  Future<void> _copyToClipboard() async {
    final text = _buildShareText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lista copiada al portapapeles'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share() async {
    final text = _buildShareText();
    // Usamos el share nativo del SO. Si printing no estuviera disponible,
    // el copy-to-clipboard ya cubre el caso. Usamos `printing` que ya está
    // en el proyecto y soporta share de texto.
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // Mostramos el sheet básico via showAdaptiveDialog para que el usuario
    // sepa que se copió y puede pegarlo donde quiera. (Si más adelante
    // queremos un share sheet real, instalamos share_plus.)
    await showDialog<void>(
      context: context,
      builder: (context) {
        final dpi = DpiScale.of(context);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(dpi.radius(20))),
          title: const Text('Lista de compras lista'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ya está copiada al portapapeles. Ábrela en WhatsApp, '
                'correo o donde la necesites y pega con la opción "Pegar".',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: dpi.space(12)),
              Container(
                padding: EdgeInsets.all(dpi.space(12)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.altSurface(context),
                  borderRadius: BorderRadius.circular(dpi.radius(8)),
                ),
                child: Text(
                  text,
                  style: TextStyle(fontSize: dpi.font(11), fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final pending = _items.where((i) => !_purchased.contains(i.itemId)).length;
    final purchased = _purchased.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de compras'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Copiar lista',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _items.isEmpty ? null : _copyToClipboard,
          ),
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _items.isEmpty ? null : _share,
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(dpi.space(40)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: dpi.icon(48), color: MangoThemeFactory.success),
                    SizedBox(height: dpi.space(12)),
                    Text(
                      'No hay insumos para reabastecer.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                _Header(pending: pending, purchased: purchased),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(12),
                        dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isPurchased = _purchased.contains(item.itemId);
                      return _ShoppingTile(
                        item: item,
                        isPurchased: isPurchased,
                        onTogglePurchased: () {
                          setState(() {
                            if (isPurchased) {
                              _purchased.remove(item.itemId);
                            } else {
                              _purchased.add(item.itemId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pending, required this.purchased});
  final int pending;
  final int purchased;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), 0),
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart_rounded, color: Colors.white, size: dpi.icon(22)),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$pending por comprar',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: dpi.font(16),
                      fontWeight: FontWeight.w800),
                ),
                if (purchased > 0)
                  Text(
                    '$purchased ya marcado${purchased == 1 ? '' : 's'} como comprado${purchased == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShoppingTile extends StatelessWidget {
  const _ShoppingTile({
    required this.item,
    required this.isPurchased,
    required this.onTogglePurchased,
  });

  final InventoryItemSnapshot item;
  final bool isPurchased;
  final VoidCallback onTogglePurchased;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final accent = item.isOut ? MangoThemeFactory.danger : MangoThemeFactory.warning;
    final suggested = item.suggestedPurchase > 0 ? item.suggestedPurchase : item.minStock;

    return InkWell(
      onTap: onTogglePurchased,
      borderRadius: BorderRadius.circular(dpi.radius(14)),
      child: Container(
        padding: EdgeInsets.all(dpi.space(14)),
        decoration: BoxDecoration(
          color: isPurchased
              ? MangoThemeFactory.altSurface(context)
              : MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(
            color: isPurchased
                ? MangoThemeFactory.borderColor(context)
                : accent.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isPurchased
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isPurchased ? MangoThemeFactory.success : accent,
              size: dpi.icon(22),
            ),
            SizedBox(width: dpi.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration:
                              isPurchased ? TextDecoration.lineThrough : TextDecoration.none,
                          color: isPurchased
                              ? MangoThemeFactory.mutedText(context)
                              : MangoThemeFactory.textColor(context),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    'Actual: ${MangoFormatters.number(item.totalQuantity.round())} ${item.unit}'
                    '${item.minStock > 0 ? ' · mín ${MangoFormatters.number(item.minStock.round())}' : ''}',
                    style: TextStyle(
                        fontSize: dpi.font(11),
                        color: MangoThemeFactory.mutedText(context)),
                  ),
                ],
              ),
            ),
            SizedBox(width: dpi.space(8)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isPurchased ? '—' : 'Comprar',
                  style: TextStyle(
                      fontSize: dpi.font(9),
                      color: MangoThemeFactory.mutedText(context)),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  isPurchased
                      ? ''
                      : '${MangoFormatters.number(suggested.round())} ${item.unit}',
                  style: TextStyle(
                    fontSize: dpi.font(14),
                    fontWeight: FontWeight.w800,
                    color: isPurchased ? MangoThemeFactory.mutedText(context) : accent,
                  ),
                ),
                if (item.isOut)
                  Container(
                    margin: EdgeInsets.only(top: dpi.space(2)),
                    padding: EdgeInsets.symmetric(
                        horizontal: dpi.space(6), vertical: dpi.space(2)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(dpi.radius(4)),
                    ),
                    child: Text(
                      'AGOTADO',
                      style: TextStyle(
                        fontSize: dpi.font(8),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
