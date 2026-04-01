import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mango_dashboard/app/app.dart';

void main() {
  testWidgets('app renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MangoDashboardApp()));
    expect(find.text('Acceso restringido'), findsOneWidget);
  });
}
