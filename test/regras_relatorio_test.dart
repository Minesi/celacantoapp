import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/ensaio_model.dart';
import 'package:celacantoapp/ensaio_evidencia_policy.dart';
import 'package:celacantoapp/filtro_model.dart';
import 'package:celacantoapp/filtro_projetos_bar.dart';
import 'package:celacantoapp/norma_calculo_service.dart';
import 'package:celacantoapp/projeto_service.dart';
import 'package:celacantoapp/sala_model.dart';
import 'package:celacantoapp/validacao_ensaio_service.dart';

FiltroModel _filtro(String id, TipoFiltro tipo, int qtd) =>
    FiltroModel(id: id, tipo: tipo, quantidade: qtd, localizacao: LocalizacaoFiltro.terminal);

void main() {
  group('Tipos de filtro G4/F9/H14', () {
    test('enum contém apenas G4, F9 e H14', () {
      expect(TipoFiltro.values.map((t) => t.name.toUpperCase()), ['G4', 'F9', 'H14']);
    });

    test('valores legados são convertidos na leitura', () {
      TipoFiltro ler(String tipo) =>
          FiltroModel.fromMap({'id': 'x', 'tipo': tipo, 'quantidade': 1, 'localizacao': 'terminal'}).tipo;
      expect(ler('grosso'), TipoFiltro.g4);
      expect(ler('fino'), TipoFiltro.f9);
      expect(ler('absoluto'), TipoFiltro.h14);
      expect(ler('h14'), TipoFiltro.h14);
    });
  });

  group('Sala -> máquina -> filtros', () {
    final sala = SalaModel(
      id: 'S1',
      nome: 'Sala 1',
      area: 10,
      volume: 30,
      grau: GrauSala.d,
      handlingUnitId: 'HU1',
      filtros: [_filtro('F1', TipoFiltro.h14, 2), _filtro('F2', TipoFiltro.g4, 1)],
    );

    test('total e unidades de filtro', () {
      expect(sala.totalFiltros, 3);
      expect(sala.unidadesDeFiltro.map((f) => f.id), ['F1', 'F1', 'F2']);
    });

    test('toMap/fromMap preserva máquina e filtros', () {
      final copia = SalaModel.fromMap(sala.toMap());
      expect(copia.handlingUnitId, 'HU1');
      expect(copia.totalFiltros, 3);
      expect(copia.filtros.first.tipo, TipoFiltro.h14);
    });

    test('sala atendida por mais de uma máquina (lista ou JSON do SQLite)', () {
      final mapa = {...sala.toMap(), 'handlingUnitIdsAdicionais': ['HU2']};
      final copia = SalaModel.fromMap(mapa);
      expect(copia.handlingUnitIds, ['HU1', 'HU2']);
      expect(copia.atendidaPor('HU2'), isTrue);
      expect(SalaModel.fromMap({...mapa, 'handlingUnitIdsAdicionais': '["HU3"]'}).handlingUnitIdsAdicionais, ['HU3']);
      expect(SalaModel.fromMap({...mapa, 'handlingUnitIdsAdicionais': null}).handlingUnitIdsAdicionais, isEmpty);
    });

    test('descrição do filtro com marca/modelo/dimensões', () {
      final filtro = FiltroModel.fromMap({
        'id': 'F', 'tipo': 'h14', 'quantidade': 2, 'localizacao': 'terminal',
        'marca': 'Trox', 'modelo': 'TFP', 'dimensoes': '610x610',
      });
      expect(filtro.descricao, '2× H14 (Trox TFP, 610x610)');
      expect(_filtro('F1', TipoFiltro.g4, 1).descricao, '1× G4');
    });
  });

  group('Ensaios por tipo de projeto', () {
    test('cada tipo de projeto mostra apenas seus ensaios aplicáveis', () {
      expect(
        EnsaioModel.catalogoDoTipo('HVAC'),
        hasLength(EnsaioModel.catalogoPadrao()
            .where((e) => e.selecionavel && e.aplicavelAoTipoProjeto('HVAC'))
            .length),
      );
      expect(EnsaioModel.catalogoDoTipo('HVAC').map((e) => e.tipo), isNot(contains(TipoEnsaio.estanqueidade)));
      expect(EnsaioModel.catalogoDoTipo('Fluxo Laminar').map((e) => e.tipo), [
        TipoEnsaio.avaliacaoFiltragem,
        TipoEnsaio.velocidadeFluxo,
        TipoEnsaio.integridadeFiltros,
        TipoEnsaio.nivelRuido,
        TipoEnsaio.luminosidade,
        TipoEnsaio.paralelismoFluxo,
        TipoEnsaio.visualizacaoFluxo,
        TipoEnsaio.contagemParticulas,
      ]);
    });
  });

  group('Evidências dos ensaios de Fluxo Laminar', () {
    test('exige foto em Contagem, Visualização e Paralelismo', () {
      expect(ensaioExigeFotoEvidencia(TipoEnsaio.contagemParticulas), isTrue);
      expect(ensaioExigeFotoEvidencia(TipoEnsaio.visualizacaoFluxo), isTrue);
      expect(ensaioExigeFotoEvidencia(TipoEnsaio.paralelismoFluxo), isTrue);
    });

    test('não exige foto nos demais ensaios', () {
      for (final tipo in [
        TipoEnsaio.avaliacaoFiltragem,
        TipoEnsaio.velocidadeFluxo,
        TipoEnsaio.integridadeFiltros,
        TipoEnsaio.nivelRuido,
        TipoEnsaio.luminosidade,
      ]) {
        expect(ensaioExigeFotoEvidencia(tipo), isFalse, reason: tipo.name);
      }
    });
  });

  group('Validação numérica dos ensaios', () {
    const validador = ValidacaoEnsaioService();

    test('rejeita texto em ensaio numérico e calcula conformidade pelo limite', () {
      final resultado = validador.validarPontos(
        tipo: TipoEnsaio.velocidadeFluxo,
        valoresPrincipais: ['0,40', 'texto'],
        configuracao: {'criterioMin': '0.50', 'criterioMax': '0.80'},
      );

      expect(resultado.valido, isFalse);
      expect(resultado.erros, contains('Ponto 2: informe um número válido.'));
      expect(resultado.conforme, isFalse);
    });

    test('valida as duas colunas da Contagem e o limite de 5 µm', () {
      final resultado = validador.validarPontos(
        tipo: TipoEnsaio.contagemParticulas,
        valoresPrincipais: ['10', '20'],
        valoresSecundarios: ['1', '6'],
        configuracao: {'criterioMax': 20, 'criterioMax5um': '5'},
      );

      expect(resultado.valido, isTrue);
      expect(resultado.conforme, isFalse);
    });

    test('mantém resultado textual sem exigir parse numérico', () {
      final resultado = validador.validarPontos(
        tipo: TipoEnsaio.visualizacaoFluxo,
        valoresPrincipais: ['Fluxo sem refluxo'],
      );

      expect(resultado.valido, isTrue);
      expect(resultado.conforme, isNull);
    });

    test('valida paralelismo como ângulo numérico', () {
      final resultado = validador.validarPontos(
        tipo: TipoEnsaio.paralelismoFluxo,
        valoresPrincipais: ['3'],
      );

      expect(resultado.valido, isTrue);
      expect(resultado.conforme, isNull);
    });
  });

  group('Pontos exigidos por sala x ensaio', () {
    final norma = NormaCalculoService();
    final sala = SalaModel(
      id: 'S1',
      nome: 'Sala 1',
      area: 10,
      volume: 30,
      grau: GrauSala.b,
      filtros: [_filtro('F1', TipoFiltro.h14, 2), _filtro('F2', TipoFiltro.f9, 1)],
    );
    final salaSemFiltro = SalaModel(id: 'S2', nome: 'Sala 2', area: 5, volume: 10, grau: GrauSala.d);

    test('ensaios por filtro exigem 1 ponto por unidade de filtro', () {
      for (final tipo in [TipoEnsaio.pressao, TipoEnsaio.estanqueidade, TipoEnsaio.integridadeFiltros]) {
        expect(norma.pontosExigidos(sala, tipo), 3, reason: tipo.name);
      }
      expect(norma.rotulosDosPontos(sala, TipoEnsaio.pressao), ['Filtro 1 (H14)', 'Filtro 2 (H14)', 'Filtro 3 (F9)']);
      expect(norma.filtrosDosPontos(sala, TipoEnsaio.pressao).map((f) => f?.id), ['F1', 'F1', 'F2']);
    });

    test('recuperação/queda de energia exigem 3 pontos fixos', () {
      expect(norma.rotulosDosPontos(sala, TipoEnsaio.quedaEnergia), ['Inicial', 'Gerada', 'Final']);
      expect(norma.filtrosDosPontos(sala, TipoEnsaio.quedaEnergia), everyElement(isNull));
    });

    test('sala sem filtros exige ao menos 1 ponto', () {
      expect(norma.pontosExigidos(salaSemFiltro, TipoEnsaio.pressao), 1);
      expect(norma.rotulosDosPontos(salaSemFiltro, TipoEnsaio.pressao), ['Ponto 1']);
    });

    test('contagem exige os pontos de repouso e operação na execução', () {
      expect(norma.pontosExigidos(salaSemFiltro, TipoEnsaio.contagemParticulas), 1);
      expect(norma.pontosExigidosParaExecucao(salaSemFiltro, TipoEnsaio.contagemParticulas), 2);
      expect(norma.pontosExigidosParaExecucao(salaSemFiltro, TipoEnsaio.pressao), 1);
    });

    test('velocidade aceita pontos por filtro armazenados como texto', () {
      final salaConfigurada = SalaModel(
        id: 'S3',
        nome: 'Sala 3',
        area: 10,
        volume: 30,
        grau: GrauSala.b,
        filtros: [_filtro('F1', TipoFiltro.h14, 2)],
        configEnsaios: {
          TipoEnsaio.velocidadeFluxo.name: {'pontos': '2'},
        },
      );
      expect(norma.pontosExigidos(salaConfigurada, TipoEnsaio.velocidadeFluxo), 4);
      expect(norma.filtrosDosPontos(salaConfigurada, TipoEnsaio.velocidadeFluxo).map((f) => f?.id), ['F1', 'F1', 'F1', 'F1']);
      expect(norma.rotulosDosPontos(salaConfigurada, TipoEnsaio.velocidadeFluxo), [
        'F1 (H14) — Ponto 1',
        'F1 (H14) — Ponto 2',
        'F2 (H14) — Ponto 1',
        'F2 (H14) — Ponto 2',
      ]);
    });
  });

  group('Separação por empresa/tipo/área/data', () {
    final base = DateTime(2026, 9, 24, 10, 30, 5);
    String chave(DateTime d, {String area = 'Área A'}) =>
        ProjetoService.chaveSeparacao(cnpjEmpresa: '11', tipoProjeto: 'HVAC', area: area, dataHora: d);

    test('mesmo minuto (segundos diferentes) gera a mesma chave', () {
      expect(chave(base), chave(base.add(const Duration(seconds: 40))));
    });

    test('minuto ou área diferentes geram chaves diferentes', () {
      expect(chave(base), isNot(chave(base.add(const Duration(minutes: 1)))));
      expect(chave(base), isNot(chave(base, area: 'Área B')));
    });

    test('filtro de listagem por CNPJ, tipo, área e data', () {
      final projetos = [
        {'cnpjEmpresa': '11', 'tipoProjeto': 'HVAC', 'area': 'Bloco A', 'dataCriacao': '2026-09-24T10:00:00'},
        {'cnpjEmpresa': '11', 'tipoProjeto': 'Fluxo Laminar', 'area': 'Bloco A', 'dataCriacao': '2026-09-24T11:00:00'},
        {'cnpjEmpresa': '22', 'tipoProjeto': 'HVAC', 'area': 'Bloco B', 'dataCriacao': '2026-09-25T10:00:00'},
      ];
      expect(const FiltroProjetos(cnpj: '11').aplicar(projetos).length, 2);
      expect(const FiltroProjetos(tipoProjeto: 'HVAC').aplicar(projetos).length, 2);
      expect(const FiltroProjetos(area: 'bloco b').aplicar(projetos).length, 1);
      expect(FiltroProjetos(data: DateTime(2026, 9, 24)).aplicar(projetos).length, 2);
      expect(const FiltroProjetos(cnpj: '11', tipoProjeto: 'HVAC').aplicar(projetos).length, 1);
    });
  });
}
