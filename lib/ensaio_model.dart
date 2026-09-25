// lib/ensaio_model.dart
import 'sala_model.dart';

enum TipoEnsaio {
  contagemParticulas,
  estanqueidade,
  pressao,
  integridadeFiltros,
  recuperacaoParticulas,
  quedaEnergia,
}

class EnsaioModel {
  final TipoEnsaio tipo;
  final String nome;
  final List<String> ferramentasNecessarias; // Tipos de instrumento exigidos por este ensaio
  final List<GrauSala> aplicavelGraus; // Graus de sala em que este ensaio é exigido

  EnsaioModel({
    required this.tipo,
    required this.nome,
    this.ferramentasNecessarias = const [],
    this.aplicavelGraus = const [GrauSala.a, GrauSala.b, GrauSala.c, GrauSala.d],
  });

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.name,
      'nome': nome,
      'ferramentasNecessarias': ferramentasNecessarias,
      'aplicavelGraus': aplicavelGraus.map((g) => g.name).toList(),
    };
  }

  factory EnsaioModel.fromMap(Map<String, dynamic> data) {
    return EnsaioModel(
      tipo: TipoEnsaio.values.firstWhere(
        (t) => t.name == data['tipo'],
        orElse: () => TipoEnsaio.pressao,
      ),
      nome: data['nome']?.toString() ?? '',
      ferramentasNecessarias: List<String>.from(data['ferramentasNecessarias'] ?? const []),
      aplicavelGraus: ((data['aplicavelGraus'] ?? const []) as List)
          .map((g) => GrauSala.values.firstWhere((x) => x.name == g, orElse: () => GrauSala.d))
          .toList(),
    );
  }

  // Catálogo inicial dos ensaios citados na reunião. Ferramentas/graus aqui são um ponto de
  // partida editável — a lista completa de tabelas por ensaio ainda é "dever de casa" do cliente.
  static List<EnsaioModel> catalogoPadrao() {
    return [
      EnsaioModel(
        tipo: TipoEnsaio.contagemParticulas,
        nome: 'Contagem de Partículas',
        ferramentasNecessarias: const ['Contador de Partículas'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.estanqueidade,
        nome: 'Estanqueidade',
        ferramentasNecessarias: const ['Balômetro'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.pressao,
        nome: 'Diferença de Pressão',
        ferramentasNecessarias: const ['Manômetro'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.integridadeFiltros,
        nome: 'Integridade de Filtros',
        ferramentasNecessarias: const ['Fotômetro'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.recuperacaoParticulas,
        nome: 'Recuperação de Partículas',
        ferramentasNecessarias: const ['Contador de Partículas'],
        aplicavelGraus: const [GrauSala.a, GrauSala.b, GrauSala.c],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.quedaEnergia,
        nome: 'Queda e Religamento de Energia',
        ferramentasNecessarias: const ['Contador de Partículas'],
        aplicavelGraus: const [GrauSala.a, GrauSala.b, GrauSala.c],
      ),
    ];
  }
}
