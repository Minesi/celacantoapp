import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/calculos_pesagem.dart';

void main() {
  test('converte dimensões do filtro de mm para m²', () {
    expect(CalculosPesagem.areaFiltroM2('1250 x 730'), closeTo(0.9125, 1e-9));
    expect(CalculosPesagem.areaFiltroM2('1250X730'), closeTo(0.9125, 1e-9));
    expect(CalculosPesagem.areaFiltroM2('610,5 x 610'), closeTo(0.372405, 1e-9));
  });

  test('retorna null quando não há dimensões válidas', () {
    expect(CalculosPesagem.areaFiltroM2(''), isNull);
    expect(CalculosPesagem.areaFiltroM2('H14'), isNull);
    expect(CalculosPesagem.areaFiltroM2('0 x 730'), isNull);
  });

  test('calcula vazão como velocidade média × área × 3600', () {
    expect(
      CalculosPesagem.vazaoM3h(velocidadeMediaMs: 0.46, areaM2: 0.9125),
      closeTo(1511.1, 0.001),
    );
  });

  test('calcula ângulo de paralelismo pelo arco-tangente de X/L', () {
    expect(CalculosPesagem.anguloParalelismoGraus(distanciaL: 900, distanciaX: 225), closeTo(14.0362, 0.0001));
    expect(CalculosPesagem.anguloParalelismoGraus(distanciaL: 900, distanciaX: -225), closeTo(14.0362, 0.0001));
    expect(CalculosPesagem.anguloParalelismoGraus(distanciaL: 0, distanciaX: 10), isNull);
  });
}
