// lib/projeto_model.dart
import 'leitura_model.dart';
import 'instrumento_model.dart'; 

class ProjetoModel {
  final String id; // ID único (CNPJ + Data/Hora)
  final String cnpjEmpresa;
  final String tipoProjeto; // HVAC, Fluxo Laminar, etc.
  final List<String> ferramentasRequeridas;
  
  // Armazena o objeto completo do instrumento (TAG, Série, Certificado) indexado pelo nome da ferramenta
  final Map<String, InstrumentoModel> ferramentasEscaneadas; 
  
  // Lista que guardará os dados capturados via OCR dos displays
  final List<LeituraModel> leiturasOcr; 

  // Construtor único e organizado
  ProjetoModel({
    required this.id,
    required this.cnpjEmpresa,
    required this.tipoProjeto,
    required this.ferramentasRequeridas,
    required this.ferramentasEscaneadas,
    this.leiturasOcr = const [],
  });
}