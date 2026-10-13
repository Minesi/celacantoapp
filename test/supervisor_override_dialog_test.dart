import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celacantoapp/supervisor_override_dialog.dart';

void main() {
  testWidgets('exige justificativa antes de tentar validar o TOTP', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ),
    );

    final liberacaoFuture = solicitarLiberacaoSupervisor(
      context: tester.element(find.byType(SizedBox)),
      titulo: 'Calibração vencida',
      mensagem: 'A ferramenta está fora da validade.',
    );
    await tester.pumpAndSettle();

    expect(find.text('Justificativa do técnico'), findsOneWidget);
    expect(find.text('Sem internet'), findsNothing);
    await tester.tap(find.text('Autorizar'));
    await tester.pump();

    expect(find.text('Informe a justificativa do técnico para continuar.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(await liberacaoFuture, isNull);
  });
}
