import 'package:flutter_test/flutter_test.dart';
import 'package:celacantoapp/instrumento_model.dart';

String _validade(DateTime data) => '${data.month.toString().padLeft(2, '0')}/${data.year}';

void main() {
  test('mantem a validade do mes corrente e dos meses futuros', () {
    final agora = DateTime.now();
    final mesAnterior = DateTime(agora.year, agora.month - 1);
    final mesSeguinte = DateTime(agora.year, agora.month + 1);

    expect(InstrumentoModel.validadeEhValida(_validade(agora)), isTrue);
    expect(InstrumentoModel.validadeEhValida(_validade(mesAnterior)), isFalse);
    expect(InstrumentoModel.validadeEhValida(_validade(mesSeguinte)), isTrue);
  });

  test('rejeita validade com mes ou formato invalido', () {
    expect(InstrumentoModel.validadeEhValida('00/2030'), isFalse);
    expect(InstrumentoModel.validadeEhValida('13/2030'), isFalse);
    expect(InstrumentoModel.validadeEhValida('2030'), isFalse);
    expect(InstrumentoModel.validadeEhValida('abc/2030'), isFalse);
  });
}
