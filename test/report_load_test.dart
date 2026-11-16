import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_dashboard/data/dashboard/report_load.dart';
import 'package:mango_dashboard/data/dashboard/report_result_cache.dart';
import 'package:mango_dashboard/presentation/dashboard/viewmodel/report_load_controller.dart';
import 'package:mango_dashboard/presentation/dashboard/widgets/report_loading.dart';
import 'package:mango_dashboard/presentation/theme/theme_data_factory.dart';

/// Deja correr las microtareas y timers de 0 ms pendientes.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Map<String, dynamic>> rows(int n) =>
    List.generate(n, (i) => <String, dynamic>{'i': i});

void main() {
  setUp(ReportResultCache.clear);
  tearDown(() => ReportResultCache.now = DateTime.now);

  group('ReportRequestThrottle', () {
    test('un reporte no ocupa más de 3 cupos a la vez', () async {
      var inFlight = 0;
      var peak = 0;
      final gates = <Completer<List<Map<String, dynamic>>>>[];

      final ticket = ReportLoadTicket();
      final load = ticket.run(() => fetchInBatches(
            List.generate(400, (i) => 'id$i'), // 10 lotes de 40
            (chunk) {
              inFlight += 1;
              if (inFlight > peak) peak = inFlight;
              final gate = Completer<List<Map<String, dynamic>>>();
              gates.add(gate);
              return gate.future.whenComplete(() => inFlight -= 1);
            },
          ));

      await settle();
      expect(peak, ReportRequestThrottle.maxBackgroundInFlight);

      // Se van soltando de a uno; nunca pasa de 3.
      var released = 0;
      while (released < 10) {
        await settle();
        final open = gates.where((g) => !g.isCompleted).toList();
        open.first.complete(rows(1));
        released += 1;
      }
      final result = await load;
      expect(result, hasLength(10));
      expect(peak, ReportRequestThrottle.maxBackgroundInFlight);
    });

    test('lo del dashboard pasa delante de los lotes de un reporte', () async {
      final order = <String>[];
      final gates = <Completer<String>>[];

      Future<String> request(String name) {
        order.add(name);
        final gate = Completer<String>();
        gates.add(gate);
        return gate.future;
      }

      final ticket = ReportLoadTicket();
      final background = [
        for (var i = 0; i < 5; i++)
          ticket.run(() => ReportRequestThrottle.run(() => request('r$i'))),
      ];
      await settle();
      expect(order, ['r0', 'r1', 'r2']); // 3 de segundo plano en vuelo

      // Petición sin ticket (dashboard): toma el 4º cupo, no espera.
      final foreground = ReportRequestThrottle.run(() => request('dash'));
      await settle();
      expect(order.last, 'dash');

      for (final gate in List.of(gates)) {
        gate.complete('ok');
      }
      await settle();
      for (final gate in gates.where((g) => !g.isCompleted).toList()) {
        gate.complete('ok');
      }
      await Future.wait([...background, foreground]);
      expect(order, ['r0', 'r1', 'r2', 'dash', 'r3', 'r4']);
    });
  });

  group('ReportLoadTicket', () {
    test('cancelar deja de pedir páginas', () async {
      var pages = 0;
      final ticket = ReportLoadTicket();
      final load = ticket.run(() => fetchAllPages((from, to) async {
            pages += 1;
            if (pages == 2) ticket.cancel();
            return rows(1000); // siempre "hay más"
          }));

      await expectLater(load, throwsA(isA<ReportLoadCancelled>()));
      expect(pages, 2);
    });

    test('cuenta peticiones y filas', () async {
      final seen = <ReportLoadProgress>[];
      final ticket = ReportLoadTicket(onProgress: seen.add);
      final result = await ticket.run(() => fetchAllPages(
            (from, to) async => rows(from == 0 ? 1000 : 250),
          ));

      expect(result, hasLength(1250));
      expect(seen.map((p) => p.requests), [1, 2]);
      expect(seen.last.rows, 1250);
    });
  });

  group('ReportResultCache', () {
    test('fresco, viejo y vencido', () {
      var clock = DateTime(2026, 10, 7, 12);
      ReportResultCache.now = () => clock;
      ReportResultCache.write('k', 42);

      expect(ReportResultCache.read<int>('k')!.isFresh, isTrue);

      clock = clock.add(const Duration(minutes: 2));
      final old = ReportResultCache.read<int>('k')!;
      expect(old.value, 42);
      expect(old.isFresh, isFalse);

      clock = clock.add(const Duration(minutes: 4));
      expect(ReportResultCache.read<int>('k'), isNull);
    });

    test('la clave separa negocio, rango y extras', () {
      final a = DateTime(2026, 10, 1);
      final b = DateTime(2026, 11, 1);
      expect(reportCacheKey('ventas', 'n1', a, b),
          isNot(reportCacheKey('ventas', 'n2', a, b)));
      expect(reportCacheKey('ventas', 'n1', a, b, [5]),
          isNot(reportCacheKey('ventas', 'n1', a, b, [0])));
    });
  });

  group('ReportLoadController', () {
    test('un resultado viejo que llega tarde no pisa al nuevo', () async {
      final controller = ReportLoadController<String>(debounce: Duration.zero);
      final first = Completer<String>();
      final second = Completer<String>();

      controller.load(key: 'hoy', fetch: () => first.future);
      await settle();
      controller.load(key: 'mes', fetch: () => second.future);
      await settle();

      second.complete('mes');
      await settle();
      first.complete('hoy');
      await settle();

      expect(controller.data, 'mes');
      expect(controller.isLoading, isFalse);
      expect(controller.isStale, isFalse);
      controller.dispose();
    });

    test('mientras carga otro periodo, lo anterior queda como viejo', () async {
      final controller = ReportLoadController<String>(debounce: Duration.zero);
      controller.load(key: 'hoy', fetch: () async => 'hoy');
      await settle();

      final pending = Completer<String>();
      controller.load(key: 'mes', fetch: () => pending.future);
      expect(controller.data, 'hoy');
      expect(controller.isStale, isTrue);
      expect(controller.isLoading, isTrue);

      pending.complete('mes');
      await settle();
      expect(controller.isStale, isFalse);
      controller.dispose();
    });

    test('lo reciente sale de la caché sin consultar', () async {
      final a = ReportLoadController<String>();
      a.load(key: 'k', fetch: () async => 'datos');
      await settle();
      a.dispose();

      var calls = 0;
      final b = ReportLoadController<String>();
      b.load(key: 'k', fetch: () async {
        calls += 1;
        return 'otra vez';
      });
      expect(b.data, 'datos');
      expect(b.isLoading, isFalse);
      await settle();
      expect(calls, 0);
      b.dispose();
    });

    test('caché vieja: se muestra ya y se refresca detrás', () async {
      var clock = DateTime(2026, 10, 7, 12);
      ReportResultCache.now = () => clock;
      ReportResultCache.write('k', 'viejo');
      clock = clock.add(const Duration(minutes: 2));

      final controller = ReportLoadController<String>();
      controller.load(key: 'k', fetch: () async => 'nuevo');
      expect(controller.data, 'viejo');
      expect(controller.isLoading, isTrue);
      expect(controller.isStale, isFalse); // mismo periodo: no se atenúa

      await settle();
      expect(controller.data, 'nuevo');
      controller.dispose();
    });

    test('si falla, guarda el error y Reintentar vuelve a pedir', () async {
      var calls = 0;
      final controller = ReportLoadController<String>(debounce: Duration.zero);
      controller.load(
        key: 'k',
        fetch: () async {
          calls += 1;
          if (calls == 1) throw Exception('red');
          return 'ok';
        },
      );
      await settle();
      expect(controller.error, isNotNull);
      expect(controller.hasData, isFalse);

      controller.retry();
      await settle();
      expect(controller.error, isNull);
      expect(controller.data, 'ok');
      controller.dispose();
    });

    test('cerrar la pantalla cancela la carga', () async {
      final controller = ReportLoadController<List<Map<String, dynamic>>>();
      var pages = 0;
      controller.load(
        key: 'k',
        fetch: () => fetchAllPages((from, to) async {
          pages += 1;
          await Future<void>.delayed(Duration.zero);
          return rows(1000);
        }),
      );
      await settle(2);
      controller.dispose();
      final pagesAtDispose = pages;
      await settle(10);
      expect(pages, lessThanOrEqualTo(pagesAtDispose + 1));
    });
  });

  group('ReportBody', () {
    Widget host(ReportLoadController<String> controller) => MaterialApp(
          theme: MangoThemeFactory.lightTheme,
          home: Scaffold(
            body: ReportBody<String>(
              controller: controller,
              builder: (context, data) => Center(child: Text('dato: $data')),
            ),
          ),
        );

    testWidgets('esqueleto, luego datos; error con Reintentar', (tester) async {
      final controller = ReportLoadController<String>(debounce: Duration.zero);
      final first = Completer<String>();
      controller.load(key: 'a', fetch: () => first.future);

      await tester.pumpWidget(host(controller));
      expect(find.byType(ReportSkeleton), findsOneWidget);
      expect(find.text('Cargando reporte…'), findsOneWidget);

      first.complete('uno');
      await tester.pumpAndSettle();
      expect(find.text('dato: uno'), findsOneWidget);
      expect(find.byType(ReportSkeleton), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing); // se plegó

      controller.load(key: 'b', fetch: () async => throw Exception('red'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('dato: uno'), findsNothing); // lo viejo no se hace pasar por el periodo nuevo

      controller.dispose();
    });
  });
}
