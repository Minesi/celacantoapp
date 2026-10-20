import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/integridade_pesagem_form.dart';

void main() {
  testWidgets('resultado parcial e ações corretivas atualizam o formulário de integridade', (tester) async {
    var valor = <String, dynamic>{};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => IntegridadePesagemForm(
              valor: valor,
              onChanged: (novo) => setState(() => valor = novo),
            ),
          ),
        ),
      ),
    ));

    final estrutura = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField && widget.decoration.labelText == 'Estrutura do filtro',
    );
    await tester.ensureVisible(estrutura);
    await tester.tap(estrutura);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não conforme').last);
    await tester.pumpAndSettle();
    expect((valor['parcial'] as Map)['estrutura'], isFalse);

    expect(find.text('Novo ensaio após ações corretivas'), findsNothing);
    await tester.ensureVisible(find.text('Reparo do filtro'));
    await tester.tap(find.text('Reparo do filtro'));
    await tester.pumpAndSettle();
    expect(valor['acoesCorretivas'], ['Reparo do filtro']);
    expect(find.text('Novo ensaio após ações corretivas'), findsOneWidget);
  });
}
