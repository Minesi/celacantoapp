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
      tipo == TipoEnsaio.avaliacaoFiltragem ||
      tipo == TipoEnsaio.velocidadeFluxo ||
      tipo == TipoEnsaio.estanqueidade ||
      tipo == TipoEnsaio.pressao ||
      tipo == TipoEnsaio.integridadeFiltros ||
      tipo == TipoEnsaio.vazaoInsuflacao ||
      tipo == TipoEnsaio.perdaCargaFiltros;

  /// Nº de pontos que o técnico precisa registrar para um ensaio numa sala.
  /// Ensaios por filtro exigem 1 ponto por unidade de filtro (saída) da sala.
  int pontosExigidos(SalaModel sala, TipoEnsaio tipo) {
    final minimoUm = sala.totalFiltros > 0 ? sala.totalFiltros : 1;
    final configuracao = sala.configEnsaios[tipo.name] ?? const <String, dynamic>{};
    final pontosConfigurados = int.tryParse(configuracao['pontos']?.toString() ?? '') ?? 0;
    switch (tipo) {
      case TipoEnsaio.avaliacaoFiltragem:
        return minimoUm;
      case TipoEnsaio.velocidadeFluxo:
        final pontosPorFiltro = pontosConfigurados > 0 ? pontosConfigurados : 1;
        return (sala.totalFiltros > 0 ? sala.totalFiltros : 1) * pontosPorFiltro;
      case TipoEnsaio.contagemParticulas:
        if (pontosConfigurados > 0) return pontosConfigurados;
        return calcularPontosContagemParticulas(sala.area) ?? minimoUm;
      case TipoEnsaio.nivelRuido:
      case TipoEnsaio.luminosidade:
      case TipoEnsaio.paralelismoFluxo:
        return pontosConfigurados > 0 ? pontosConfigurados : 1;
      case TipoEnsaio.recuperacaoParticulas:
      case TipoEnsaio.quedaEnergia:
        return 3; // inicial / gerada / final
      case TipoEnsaio.visualizacaoFluxo:
        return 1;
      case TipoEnsaio.estanqueidade:
      case TipoEnsaio.pressao:
      case TipoEnsaio.integridadeFiltros:
      case TipoEnsaio.vazaoInsuflacao:
      case TipoEnsaio.perdaCargaFiltros:
        return minimoUm;
    }
  }

  int pontosExigidosParaExecucao(SalaModel sala, TipoEnsaio tipo) {
    final pontos = pontosExigidos(sala, tipo);
    return tipo == TipoEnsaio.contagemParticulas ? pontos * 2 : pontos;
  }

  /// Filtro correspondente a cada ponto (null quando o ensaio não é por filtro).
  List<FiltroModel?> filtrosDosPontos(SalaModel sala, TipoEnsaio tipo) {
    final total = pontosExigidos(sala, tipo);
    final unidades = sala.unidadesDeFiltro;
    if (!ensaioPorFiltro(tipo) || unidades.isEmpty) return List.filled(total, null);
    if (tipo == TipoEnsaio.velocidadeFluxo) {
      final pontosPorFiltro = int.tryParse(sala.configEnsaios[tipo.name]?['pontos']?.toString() ?? '') ?? 1;
      return [
        for (final filtro in unidades)
          for (var ponto = 0; ponto < pontosPorFiltro; ponto++) filtro,
      ];
    }
    return unidades;
  }

  List<String> rotulosDosPontos(SalaModel sala, TipoEnsaio tipo) {
    final total = pontosExigidos(sala, tipo);
    if (tipo == TipoEnsaio.recuperacaoParticulas || tipo == TipoEnsaio.quedaEnergia) {
      return const ['Inicial', 'Gerada', 'Final'];
    }
    if (tipo == TipoEnsaio.visualizacaoFluxo) return const ['Sentido do fluxo'];
    final filtros = filtrosDosPontos(sala, tipo);
    return List.generate(total, (i) {
      final filtro = filtros[i];
      if (filtro == null) return 'Ponto ${i + 1}';
      if (tipo == TipoEnsaio.velocidadeFluxo) {
        final pontosPorFiltro = int.tryParse(sala.configEnsaios[tipo.name]?['pontos']?.toString() ?? '') ?? 1;
        final numeroFiltro = (i ~/ pontosPorFiltro) + 1;
        final indiceFiltro = (i % pontosPorFiltro) + 1;
        return 'F$numeroFiltro (${filtro.tipo.name.toUpperCase()}) — Ponto $indiceFiltro';
      }
      return 'Filtro ${i + 1} (${filtro.tipo.name.toUpperCase()})';
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
