/// Tipo de descuento de una oferta (`promotions.discount_type`).
/// Alcance "Completo": solo % y monto fijo (sin BOGO/combo).
enum DiscountType {
  percentage,
  fixed;

  static DiscountType fromRaw(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'fixed':
        return DiscountType.fixed;
      case 'percentage':
      default:
        return DiscountType.percentage;
    }
  }

  String get raw {
    switch (this) {
      case DiscountType.percentage:
        return 'percentage';
      case DiscountType.fixed:
        return 'fixed';
    }
  }

  String get label {
    switch (this) {
      case DiscountType.percentage:
        return 'Porcentaje';
      case DiscountType.fixed:
        return 'Monto fijo';
    }
  }
}

/// A qué aplica la oferta (`promotions.applies_to`).
enum AppliesTo {
  all,
  category,
  product;

  static AppliesTo fromRaw(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'category':
        return AppliesTo.category;
      case 'product':
        return AppliesTo.product;
      case 'all':
      default:
        return AppliesTo.all;
    }
  }

  String get raw {
    switch (this) {
      case AppliesTo.all:
        return 'all';
      case AppliesTo.category:
        return 'category';
      case AppliesTo.product:
        return 'product';
    }
  }

  String get label {
    switch (this) {
      case AppliesTo.all:
        return 'Todo el menú';
      case AppliesTo.category:
        return 'Categorías';
      case AppliesTo.product:
        return 'Productos';
    }
  }
}

/// Etiquetas cortas de los días de la semana (Postgres: 0=domingo … 6=sábado).
const List<String> kWeekdayLabels = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
