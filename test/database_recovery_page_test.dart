import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celacantoapp/database_recovery_page.dart';

void main() {
  testWidgets('pede confirmacao antes de reconstruir o banco local', (tester) async {
    var recuperado = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseRecoveryPage(
          onRecuperado: () => recuperado = true,
          paginaInicial: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.text('Reconstruir banco local'));
    await tester.pumpAndSettle();

    expect(find.text('Reconstruir banco local?'), findsOneWidget);
    expect(recuperado, isFalse);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Reconstruir banco local?'), findsNothing);
    expect(recuperado, isFalse);
  });
}
