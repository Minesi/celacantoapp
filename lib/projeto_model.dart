// lib/projeto_model.dart
import 'leitura_model.dart';
import 'instrumento_model.dart';
import 'sala_model.dart';
import 'handling_unit_model.dart';
import 'history_entry_model.dart';
import 'paralelismo_model.dart';

// Fluxo de aprovação do relatório: elaboração -> campo -> revisão -> aprovação
// (a geração do .docx final é disparada na transição para `aprovado`).
enum StatusRelatorio { rascunho, prontoParaCampo, emRevisao, aprovado }

class ProjetoModel {
  final String id; // ID único (CNPJ + Data/Hora)
  final String cnpjEmpresa;
  final String tipoProjeto; // HVAC, Fluxo Laminar, etc.
  final List<String> ferramentasRequeridas;
  
  // Indexado pelo nome da ferramenta; lista porque um mesmo tipo pode usar mais de um
  // instrumento no mesmo ensaio (ex.: 3 contadores de partículas em ambientes grandes).
  final Map<String, List<InstrumentoModel>> ferramentasEscaneadas; 
  
  // Lista que guardará os dados capturados via OCR dos displays
  final List<LeituraModel> leiturasOcr; 

  // --- Campos levantados na reunião de requisitos (estrutura de sistema/área/salas) ---
  final String sistemaId; // Referência ao SistemaModel selecionado (ex.: "HDA04")
  final String area; // Área atendida pelo sistema, definida na etapa de elaboração
  final List<SalaModel> salas;
  final List<HandlingUnitModel> handlingUnits;
  final List<String> ensaiosSelecionados; // Tipos de EnsaioModel escolhidos para o projeto
  final StatusRelatorio status;
  final List<HistoryEntry> history;
  final RegistroParalelismo? paralelismo;
  final int? validadeTestesMeses;

  // Construtor único e organizado
  ProjetoModel({
    required this.id,
    required this.cnpjEmpresa,
    required this.tipoProjeto,
    required this.ferramentasRequeridas,
    required this.ferramentasEscaneadas,
    this.leiturasOcr = const [],
    this.sistemaId = '',
    this.area = '',
    this.salas = const [],
    this.handlingUnits = const [],
    this.ensaiosSelecionados = const [],
    this.status = StatusRelatorio.rascunho,
    this.history = const [],
    this.paralelismo,
    this.validadeTestesMeses,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cnpjEmpresa': cnpjEmpresa,
      'tipoProjeto': tipoProjeto,
      'ferramentasRequeridas': ferramentasRequeridas,
      'ferramentasEscaneadas': ferramentasEscaneadas.map((k, v) => MapEntry(k, v.map((i) => i.toMap()).toList())),
      'leiturasOcr': leiturasOcr.map((l) => l.toMap()).toList(),
      'sistemaId': sistemaId,
      'area': area,
      'salas': salas.map((s) => s.toMap()).toList(),
      'handlingUnits': handlingUnits.map((h) => h.toMap()).toList(),
      'ensaiosSelecionados': ensaiosSelecionados,
      'status': status.name,
      'history': history.map((h) => h.toMap()).toList(),
      'paralelismo': paralelismo?.toMap(),
      'validadeTestesMeses': validadeTestesMeses,
    };
  }

  factory ProjetoModel.fromMap(Map<String, dynamic> data) {
    final ferramentasEscaneadas = <String, List<InstrumentoModel>>{};
    (data['ferramentasEscaneadas'] as Map<String, dynamic>? ?? {}).forEach((tipo, instrumentos) {
      ferramentasEscaneadas[tipo] = (instrumentos as List)
          .map((i) => InstrumentoModel.fromFirestore(Map<String, dynamic>.from(i), ''))
          .toList();
    });

    return ProjetoModel(
      id: data['id']?.toString() ?? '',
      cnpjEmpresa: data['cnpjEmpresa']?.toString() ?? '',
      tipoProjeto: data['tipoProjeto']?.toString() ?? '',
      ferramentasRequeridas: List<String>.from(data['ferramentasRequeridas'] ?? const []),
      ferramentasEscaneadas: ferramentasEscaneadas,
      leiturasOcr: ((data['leiturasOcr'] ?? const []) as List)
          .map((l) => LeituraModel.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      sistemaId: data['sistemaId']?.toString() ?? '',
      area: data['area']?.toString() ?? '',
      salas: ((data['salas'] ?? const []) as List)
          .map((s) => SalaModel.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      handlingUnits: ((data['handlingUnits'] ?? const []) as List)
          .map((h) => HandlingUnitModel.fromMap(Map<String, dynamic>.from(h)))
          .toList(),
      ensaiosSelecionados: List<String>.from(data['ensaiosSelecionados'] ?? const []),
      status: StatusRelatorio.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => StatusRelatorio.rascunho,
      ),
      history: ((data['history'] ?? const []) as List)
          .map((h) => HistoryEntry.fromMap(Map<String, dynamic>.from(h)))
          .toList(),
      paralelismo: data['paralelismo'] is Map
          ? RegistroParalelismo.fromMap(Map<String, dynamic>.from(data['paralelismo']))
          : null,
        validadeTestesMeses: data['validadeTestesMeses'] is num
          ? (data['validadeTestesMeses'] as num).toInt()
          : int.tryParse(data['validadeTestesMeses']?.toString() ?? ''),
    );
  }
}