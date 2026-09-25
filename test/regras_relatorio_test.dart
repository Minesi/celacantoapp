import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/ensaio_model.dart';
import 'package:celacantoapp/filtro_model.dart';
import 'package:celacantoapp/filtro_projetos_bar.dart';
import 'package:celacantoapp/norma_calculo_service.dart';
import 'package:celacantoapp/projeto_service.dart';
import 'package:celacantoapp/sala_model.dart';

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
