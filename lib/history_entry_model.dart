// lib/history_entry_model.dart
// Registro de auditoria de alterações relevantes no relatório (quem, quando, campo,
// valor antigo/novo) — espelha a necessidade de rastreabilidade levantada na reunião.
class HistoryEntry {
  final String usuario;
  final DateTime dataHora;
  final String campo;
  final String valorAntigo;
  final String valorNovo;
  final Map<String, dynamic> detalhes;

  HistoryEntry({
    required this.usuario,
    required this.dataHora,
    required this.campo,
    required this.valorAntigo,
    required this.valorNovo,
    this.detalhes = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'usuario': usuario,
      'dataHora': dataHora.toIso8601String(),
      'campo': campo,
      'valorAntigo': valorAntigo,
      'valorNovo': valorNovo,
      if (detalhes.isNotEmpty) 'detalhes': detalhes,
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> data) {
    return HistoryEntry(
      usuario: data['usuario']?.toString() ?? '',
      dataHora: DateTime.tryParse(data['dataHora']?.toString() ?? '') ?? DateTime.now(),
      campo: data['campo']?.toString() ?? '',
      valorAntigo: data['valorAntigo']?.toString() ?? '',
      valorNovo: data['valorNovo']?.toString() ?? '',
      detalhes: data['detalhes'] is Map ? Map<String, dynamic>.from(data['detalhes'] as Map) : const {},
    );
  }
}
