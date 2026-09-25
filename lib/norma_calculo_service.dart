// lib/norma_calculo_service.dart
// Motor de cálculo configurável para regras de norma técnica (contagem de partículas, trocas de ar).
// Nenhum valor da norma é fixado aqui: a tabela real e a fórmula para áreas acima do limite ainda
// não foram enviadas pelo cliente ("dever de casa" da reunião de requisitos) e devem ser injetadas
// via configuração assim que estiverem disponíveis.
import 'ensaio_model.dart';
import 'filtro_model.dart';
import 'sala_model.dart';

class FaixaPontosContagem {
  final double areaMaximaM2; // Limite superior (inclusive) desta faixa
  final int pontosExigidos;

  const FaixaPontosContagem({required this.areaMaximaM2, required this.pontosExigidos});
}

class NormaCalculoService {
  /// Tabela de referência (área -> nº de pontos exigidos), ordenada por área crescente.
  final List<FaixaPontosContagem> tabelaPontosContagem;

  /// Fórmula usada para áreas acima do limite coberto pela tabela.
  final int Function(double areaM2)? formulaAcimaDoLimite;

  NormaCalculoService({
    this.tabelaPontosContagem = const [],
    this.formulaAcimaDoLimite,
  });

  /// Nº de pontos de leitura de contagem de partículas exigidos para uma sala.
  /// Retorna null quando a tabela/fórmula ainda não foi configurada.
  int? calcularPontosContagemParticulas(double areaM2) {
    for (final faixa in tabelaPontosContagem) {
      if (areaM2 <= faixa.areaMaximaM2) {
        return faixa.pontosExigidos;
      }
    }
    return formulaAcimaDoLimite?.call(areaM2);
  }

  static bool ensaioPorFiltro(TipoEnsaio tipo) =>
      tipo == TipoEnsaio.estanqueidade || tipo == TipoEnsaio.pressao || tipo == TipoEnsaio.integridadeFiltros;

  /// Nº de pontos que o técnico precisa registrar para um ensaio numa sala.
  /// Ensaios por filtro exigem 1 ponto por unidade de filtro (saída) da sala.
  int pontosExigidos(SalaModel sala, TipoEnsaio tipo) {
    final minimoUm = sala.totalFiltros > 0 ? sala.totalFiltros : 1;
    switch (tipo) {
      case TipoEnsaio.contagemParticulas:
        return calcularPontosContagemParticulas(sala.area) ?? minimoUm;
      case TipoEnsaio.recuperacaoParticulas:
      case TipoEnsaio.quedaEnergia:
        return 3; // inicial / gerada / final
      case TipoEnsaio.estanqueidade:
      case TipoEnsaio.pressao:
      case TipoEnsaio.integridadeFiltros:
        return minimoUm;
    }
  }

  /// Filtro correspondente a cada ponto (null quando o ensaio não é por filtro).
  List<FiltroModel?> filtrosDosPontos(SalaModel sala, TipoEnsaio tipo) {
    final total = pontosExigidos(sala, tipo);
    final unidades = sala.unidadesDeFiltro;
    if (!ensaioPorFiltro(tipo) || unidades.isEmpty) return List.filled(total, null);
    return unidades;
  }

  List<String> rotulosDosPontos(SalaModel sala, TipoEnsaio tipo) {
    final total = pontosExigidos(sala, tipo);
    if (tipo == TipoEnsaio.recuperacaoParticulas || tipo == TipoEnsaio.quedaEnergia) {
      return const ['Inicial', 'Gerada', 'Final'];
    }
    final filtros = filtrosDosPontos(sala, tipo);
    return List.generate(total, (i) {
      final filtro = filtros[i];
      return filtro == null ? 'Ponto ${i + 1}' : 'Filtro ${i + 1} (${filtro.tipo.name.toUpperCase()})';
    });
  }

  /// Nº de trocas de ar por hora = soma das vazões medidas (m³/h) / volume da sala (m³).
  double calcularNumeroTrocasDeAr({
    required List<double> vazoesPorDifusor,
    required double volumeSalaM3,
  }) {
    if (volumeSalaM3 <= 0) return 0;
    final somaVazoes = vazoesPorDifusor.fold<double>(0, (soma, v) => soma + v);
    return somaVazoes / volumeSalaM3;
  }
}
