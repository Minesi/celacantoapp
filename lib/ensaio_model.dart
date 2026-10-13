// lib/ensaio_model.dart
import 'sala_model.dart';

enum TipoEnsaio {
  avaliacaoFiltragem,
  velocidadeFluxo,
  contagemParticulas,
  estanqueidade, // legado: substituído por integridadeFiltros (Integridade e Estanqueidade)
  pressao,
  integridadeFiltros,
  nivelRuido,
  luminosidade,
  paralelismoFluxo,
  recuperacaoParticulas,
  quedaEnergia,
  vazaoInsuflacao,
  perdaCargaFiltros,
  visualizacaoFluxo,
}

class EnsaioModel {
  final TipoEnsaio tipo;
  final String nome;
  final List<String> ferramentasNecessarias; // Tipos de instrumento exigidos por este ensaio
  final List<GrauSala> aplicavelGraus; // Graus de sala em que este ensaio é exigido
  final List<String> aplicavelTiposProjeto; // Vazio = todos os tipos de projeto
  final bool selecionavel; // false = só mantido para abrir projetos antigos

  EnsaioModel({
    required this.tipo,
    required this.nome,
    this.ferramentasNecessarias = const [],
    this.aplicavelGraus = const [GrauSala.a, GrauSala.b, GrauSala.c, GrauSala.d],
    this.aplicavelTiposProjeto = const [],
    this.selecionavel = true,
  });

  bool aplicavelAoTipoProjeto(String? tipoProjeto) =>
      aplicavelTiposProjeto.isEmpty || aplicavelTiposProjeto.contains(tipoProjeto);

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.name,
      'nome': nome,
      'ferramentasNecessarias': ferramentasNecessarias,
      'aplicavelGraus': aplicavelGraus.map((g) => g.name).toList(),
      'aplicavelTiposProjeto': aplicavelTiposProjeto,
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
      aplicavelTiposProjeto: List<String>.from(data['aplicavelTiposProjeto'] ?? const []),
    );
  }

  static const String tipoFluxoLaminar = 'Fluxo Laminar';
  static const String tipoCabineSegurancaBiologica = 'Cabine de Segurança Biológica';
  static const String tipoCapelaExaustao = 'Capela de Exaustão';
  static const String tipoHvac = 'HVAC';
  static const String tipoPesagem = 'Pesagem';

  static const List<String> tiposDeProjeto = [
    tipoFluxoLaminar,
    tipoCabineSegurancaBiologica,
    tipoCapelaExaustao,
    tipoHvac,
    tipoPesagem,
  ];

  static List<EnsaioModel> catalogoDoTipo(String? tipoProjeto) =>
      catalogoPadrao().where((e) => e.selecionavel && e.aplicavelAoTipoProjeto(tipoProjeto)).toList();

  // Mesma ordem dos testes do relatório de qualificação (numeração TESTE 1..N segue esta lista).
  static List<EnsaioModel> catalogoPadrao() {
    return [
      EnsaioModel(
        tipo: TipoEnsaio.avaliacaoFiltragem,
        nome: 'Avaliação do Sistema de Filtragem',
        ferramentasNecessarias: const ['Manômetro'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.velocidadeFluxo,
        nome: 'Velocidade e Uniformidade do Fluxo de Ar',
        ferramentasNecessarias: const ['Anemômetro'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.vazaoInsuflacao,
        nome: 'Vazão de Insuflação e Nº de Trocas de Ar',
        ferramentasNecessarias: const ['Balômetro'],
        aplicavelTiposProjeto: const [tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.perdaCargaFiltros,
        nome: 'Perda de Carga dos Filtros HEPA',
        ferramentasNecessarias: const ['Manômetro'],
        aplicavelTiposProjeto: const [tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.integridadeFiltros,
        nome: 'Integridade de Filtros',
        ferramentasNecessarias: const ['Fotômetro'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.nivelRuido,
        nome: 'Nível de Ruído',
        ferramentasNecessarias: const ['Decibelímetro'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.luminosidade,
        nome: 'Luminosidade',
        ferramentasNecessarias: const ['Luxímetro'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.paralelismoFluxo,
        nome: 'Paralelismo do Fluxo de Ar',
        ferramentasNecessarias: const ['Máquina de Fumaça'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.pressao,
        nome: 'Diferença de Pressão',
        ferramentasNecessarias: const ['Manômetro'],
        aplicavelTiposProjeto: const [tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.visualizacaoFluxo,
        nome: 'Visualização do Fluxo de Ar',
        ferramentasNecessarias: const ['Máquina de Fumaça'],
        aplicavelTiposProjeto: const [tipoFluxoLaminar, tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.contagemParticulas,
        nome: 'Contagem de Partículas',
        ferramentasNecessarias: const ['Contador de Partículas'],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.recuperacaoParticulas,
        nome: 'Recuperação de Partículas',
        ferramentasNecessarias: const ['Contador de Partículas'],
        aplicavelGraus: const [GrauSala.a, GrauSala.b, GrauSala.c],
        aplicavelTiposProjeto: const [tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.quedaEnergia,
        nome: 'Queda e Religamento de Energia',
        ferramentasNecessarias: const ['Contador de Partículas'],
        aplicavelGraus: const [GrauSala.a, GrauSala.b, GrauSala.c],
        aplicavelTiposProjeto: const [tipoHvac],
      ),
      EnsaioModel(
        tipo: TipoEnsaio.estanqueidade,
        nome: 'Estanqueidade',
        ferramentasNecessarias: const ['Balômetro'],
        aplicavelTiposProjeto: const [tipoHvac],
        selecionavel: false,
      ),
    ];
  }
}
