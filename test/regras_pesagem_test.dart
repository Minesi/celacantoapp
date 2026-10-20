import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/regras_pesagem.dart';

void main() {
  test('velocidade é conforme quando a média está na faixa e o desvio relativo até 15%', () {
    expect(RegrasPesagem.velocidadeConforme([0.44, 0.46, 0.45]), isTrue);
  });

  test('velocidade é não conforme com média fora da faixa ou desvio acima de 15%', () {
    expect(RegrasPesagem.velocidadeConforme([0.30, 0.31]), isFalse);
    expect(RegrasPesagem.velocidadeConforme([0.20, 0.50, 0.50]), isFalse);
  });

  test('velocidade fica pendente enquanto faltar algum ponto', () {
    expect(RegrasPesagem.velocidadeConforme([0.46, null]), isNull);
    expect(RegrasPesagem.velocidadeConforme([]), isNull);
  });

  test('calcula vazão por filtro a partir da média dos seus pontos', () {
    final vazoes = RegrasPesagem.vazaoPorFiltro([
      const MedicaoVelocidadeFiltro(dimensoes: '1250 x 730', velocidades: [0.46]),
      const MedicaoVelocidadeFiltro(dimensoes: 'H14', velocidades: [0.5]),
    ]);

    expect(vazoes[0].vazaoM3h, closeTo(1511.1, 0.001));
    expect(vazoes[1].areaM2, isNull);
    expect(vazoes[1].vazaoM3h, isNull);
  });

  test('visualização falha se qualquer verificação falhar', () {
    expect(RegrasPesagem.visualizacaoConforme([true, true]), isTrue);
    expect(RegrasPesagem.visualizacaoConforme([true, false]), isFalse);
    expect(RegrasPesagem.visualizacaoConforme([true, null]), isNull);
  });

  test('integridade usa o limite de 0,01% por filtro', () {
    expect(RegrasPesagem.integridadeConforme([0.005, 0.01]), isTrue);
    expect(RegrasPesagem.integridadeConforme([0.005, 0.02]), isFalse);
  });

  test('paralelismo usa o limite de 14 graus', () {
    expect(RegrasPesagem.paralelismoConforme([3, 14]), isTrue);
    expect(RegrasPesagem.paralelismoConforme([3, 15]), isFalse);
  });

  test('converte número com vírgula decimal', () {
    expect(RegrasPesagem.numero('0,46'), closeTo(0.46, 1e-9));
    expect(RegrasPesagem.numero(''), isNull);
  });

  test('integridade final prevalece o novo ensaio após ações corretivas', () {
    expect(
      RegrasPesagem.integridadeFinal(concentracoesPct: [0.5], resultadoParcial: [true, true, true], novoEnsaioConforme: true),
      isTrue,
    );
    expect(
      RegrasPesagem.integridadeFinal(concentracoesPct: [0.005], resultadoParcial: [true, false, true]),
      isFalse,
    );
    expect(
      RegrasPesagem.integridadeFinal(concentracoesPct: [0.005], resultadoParcial: [true, null, true]),
      isNull,
    );
    expect(
      RegrasPesagem.integridadeFinal(concentracoesPct: [0.005], resultadoParcial: [true, true, true]),
      isTrue,
    );
  });

  test('contagem Grau C usa limites diferentes em repouso e em operação', () {
    expect(RegrasPesagem.limitesContagemGrauC(operacao: false), {'criterioMax': 352000, 'criterioMax5um': 2900});
    expect(RegrasPesagem.limitesContagemGrauC(operacao: true), {'criterioMax': 3520000, 'criterioMax5um': 29000});
  });

  test('limite da contagem por estado prevalece sobre o geral e o padrão', () {
    const padrao = {'criterioMax': 352000, 'criterioMax5um': 2900};
    final config = {'criterioMax_repouso': '100000', 'criterioMax': '500000', 'criterioMax5um_repouso': ''};
    expect(
      RegrasPesagem.criteriosContagemPorEstado(estado: 'repouso', config: config, padrao: padrao),
      {'criterioMax': '100000', 'criterioMax5um': 2900},
    );
    expect(
      RegrasPesagem.criteriosContagemPorEstado(estado: 'operacao', config: config, padrao: padrao),
      {'criterioMax': '500000', 'criterioMax5um': 2900},
    );
  });
}
