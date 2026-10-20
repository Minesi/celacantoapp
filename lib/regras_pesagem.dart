// lib/regras_pesagem.dart
// Critérios de aceitação do modelo de Pesagem (anexos 1 a 8), sem dependência de tela ou banco.
import 'dart:math' as math;

import 'calculos_pesagem.dart';

class MedicaoVelocidadeFiltro {
  final String dimensoes;
  final List<double> velocidades;

  const MedicaoVelocidadeFiltro({required this.dimensoes, required this.velocidades});
}

class VazaoFiltro {
  final double? mediaMs;
  final double? areaM2;
  final double? vazaoM3h;

  const VazaoFiltro({this.mediaMs, this.areaM2, this.vazaoM3h});

  Map<String, dynamic> paraMapa() => {'mediaMs': mediaMs, 'areaM2': areaM2, 'vazaoM3h': vazaoM3h};
}

class RegrasPesagem {
  const RegrasPesagem._();

  static const double velocidadeMinMs = 0.36;
  static const double velocidadeMaxMs = 0.54;
  static const double desvioRelativoMaxPct = 15;
  static const double integridadeMaxPct = 0.01;
  static const double paralelismoMaxGraus = 14;
  static const Map<String, dynamic> limiteRuidoPesagem = {'criterioMax': 85};

  static double? numero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

  /// Desvio-padrão amostral relativo (%) à média; null sem valores ou com média zero.
  static double? desvioPadraoRelativoPct(List<double> valores) {
    if (valores.isEmpty) return null;
    final media = valores.reduce((a, b) => a + b) / valores.length;
    if (media == 0) return null;
    final somaQuadrados = valores.fold<double>(0, (soma, valor) => soma + (valor - media) * (valor - media));
    final desvio = valores.length > 1 ? math.sqrt(somaQuadrados / (valores.length - 1)) : 0.0;
    return desvio / media * 100;
  }

  /// Critério sobre a média e o desvio relativo; null enquanto faltar algum ponto.
  static bool? velocidadeConforme(List<double?> velocidades) {
    if (velocidades.isEmpty || velocidades.contains(null)) return null;
    final valores = velocidades.cast<double>();
    final media = valores.reduce((a, b) => a + b) / valores.length;
    final desvio = desvioPadraoRelativoPct(valores);
    return media >= velocidadeMinMs &&
        media <= velocidadeMaxMs &&
        desvio != null &&
        desvio <= desvioRelativoMaxPct;
  }

  static List<VazaoFiltro> vazaoPorFiltro(List<MedicaoVelocidadeFiltro> medicoes) => [
        for (final medicao in medicoes) _vazao(medicao),
      ];

  static VazaoFiltro _vazao(MedicaoVelocidadeFiltro medicao) {
    if (medicao.velocidades.isEmpty) return const VazaoFiltro();
    final media = medicao.velocidades.reduce((a, b) => a + b) / medicao.velocidades.length;
    final area = CalculosPesagem.areaFiltroM2(medicao.dimensoes);
    return VazaoFiltro(
      mediaMs: media,
      areaM2: area,
      vazaoM3h: area == null ? null : CalculosPesagem.vazaoM3h(velocidadeMediaMs: media, areaM2: area),
    );
  }

  /// Todos os itens conformes; falha se algum falhar, null enquanto algum não tiver resposta.
  static bool? todosConformes(List<bool?> itens) {
    if (itens.isEmpty) return null;
    if (itens.contains(false)) return false;
    if (itens.contains(null)) return null;
    return true;
  }

  static bool? visualizacaoConforme(List<bool?> verificacoes) => todosConformes(verificacoes);

  /// Um novo ensaio após ações corretivas prevalece sobre a medição inicial.
  static bool? integridadeFinal({
    required List<double?> concentracoesPct,
    required List<bool?> resultadoParcial,
    bool? novoEnsaioConforme,
  }) {
    if (novoEnsaioConforme != null) return novoEnsaioConforme;
    final concentracoes = integridadeConforme(concentracoesPct);
    final parcial = todosConformes(resultadoParcial);
    if (concentracoes == null || parcial == null) return null;
    return concentracoes && parcial;
  }

  /// Limites da Contagem para Grau C (anexo 7), em partículas por m³.
  static Map<String, dynamic> limitesContagemGrauC({required bool operacao}) => operacao
      ? const {'criterioMax': 3520000, 'criterioMax5um': 29000}
      : const {'criterioMax': 352000, 'criterioMax5um': 2900};

  /// Limites por estado: elaboração (por estado, depois geral) ou padrão; campos vazios usam o padrão.
  static Map<String, dynamic> criteriosContagemPorEstado({
    required String estado,
    Map<String, dynamic> config = const {},
    Map<String, dynamic> padrao = const {},
  }) {
    dynamic escolher(String campo) {
      for (final chave in ['${campo}_$estado', campo]) {
        final valor = config[chave];
        if (valor != null && valor.toString().trim().isNotEmpty) return valor;
      }
      return padrao[campo];
    }

    final max05 = escolher('criterioMax');
    final max5 = escolher('criterioMax5um');
    return {
      'criterioMax': ?max05,
      'criterioMax5um': ?max5,
    };
  }

  static bool? integridadeConforme(List<double?> concentracoesPct) {
    if (concentracoesPct.isEmpty || concentracoesPct.contains(null)) return null;
    return concentracoesPct.every((valor) => valor! <= integridadeMaxPct);
  }

  static bool? paralelismoConforme(List<double?> angulosGraus) {
    if (angulosGraus.isEmpty || angulosGraus.contains(null)) return null;
    return angulosGraus.every((valor) => valor! <= paralelismoMaxGraus);
  }
}
