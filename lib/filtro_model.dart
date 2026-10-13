// lib/filtro_model.dart
enum TipoFiltro { g4, f9, h14 }

// Valores gravados antes da troca para G4/F9/H14.
const Map<String, TipoFiltro> _tiposFiltroLegados = {
  'grosso': TipoFiltro.g4,
  'fino': TipoFiltro.f9,
  'absoluto': TipoFiltro.h14,
};

extension TipoFiltroRotulo on TipoFiltro {
  String get rotulo => switch (this) {
        TipoFiltro.g4 => 'Grosso (G4)',
        TipoFiltro.f9 => 'Fino (F9)',
        TipoFiltro.h14 => 'Absoluto (H14)',
      };
}

enum LocalizacaoFiltro { maquina, terminal }

class FiltroModel {
  final String id;
  final TipoFiltro tipo;
  final int quantidade;
  final LocalizacaoFiltro localizacao;
  final String marca;
  final String modelo;
  final String dimensoes;

  FiltroModel({
    required this.id,
    required this.tipo,
    required this.quantidade,
    required this.localizacao,
    this.marca = '',
    this.modelo = '',
    this.dimensoes = '',
  });

  /// Ex.: "2× G4 (Trox TFP, 610x610x48)".
  String get descricao {
    final detalhes = [
      [marca, modelo].where((s) => s.isNotEmpty).join(' '),
      dimensoes,
    ].where((s) => s.isNotEmpty).join(', ');
    return '$quantidade× ${tipo.name.toUpperCase()}${detalhes.isEmpty ? '' : ' ($detalhes)'}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo.name,
      'quantidade': quantidade,
      'localizacao': localizacao.name,
      'marca': marca,
      'modelo': modelo,
      'dimensoes': dimensoes,
    };
  }

  factory FiltroModel.fromMap(Map<String, dynamic> data) {
    return FiltroModel(
      id: data['id']?.toString() ?? '',
      tipo: TipoFiltro.values.firstWhere(
        (t) => t.name == data['tipo'],
        orElse: () => _tiposFiltroLegados[data['tipo']] ?? TipoFiltro.g4,
      ),
      quantidade: data['quantidade'] is int
          ? data['quantidade']
          : int.tryParse(data['quantidade']?.toString() ?? '') ?? 0,
      localizacao: LocalizacaoFiltro.values.firstWhere(
        (l) => l.name == data['localizacao'],
        orElse: () => LocalizacaoFiltro.maquina,
      ),
      marca: data['marca']?.toString() ?? '',
      modelo: data['modelo']?.toString() ?? '',
      dimensoes: data['dimensoes']?.toString() ?? '',
    );
  }
}
