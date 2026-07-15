// lib/empresa_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'empresa_model.dart';
import 'projeto_model.dart';
import 'instrumento_model.dart';

class EmpresaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Auxiliar para extrair o domínio corporativo pós-@
  String _extrairDominio(String email) {
    if (!email.contains('@')) return '';
    return email.trim().toLowerCase().split('@').last;
  }

  // =========================================================================
  // --- FLUXO DE GERENCIAMENTO DE EMPRESAS ---
  // =========================================================================

  /// Salva uma nova empresa utilizando o domínio do e-mail como ID do documento
  Future<bool> salvarNovaEmpresa({
    required String razaoSocial,
    required String nomeFantasia,
    required String cnpj,
    required String emailResponsavel,
  }) async {
    try {
      String dominio = _extrairDominio(emailResponsavel);
      if (dominio.isEmpty) return false;

      EmpresaModel novaEmpresa = EmpresaModel(
        dominio: dominio,
        razaoSocial: razaoSocial.trim(),
        nomeFantasia: nomeFantasia.trim(),
        cnpj: cnpj.trim(),
        projetosModelo: [],
        projetosFinais: [],
      );

      // Salva na nuvem (Se estiver offline, salva no cache local e sincroniza depois)
      await _firestore
          .collection('empresas')
          .doc(dominio)
          .set(novaEmpresa.toMap());

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Recupera todas as empresas cadastradas (Usa cache local automaticamente se offline)
  Future<List<EmpresaModel>> buscarTodasEmpresas() async {
    try {
      final querySnapshot = await _firestore.collection('empresas').get();
      
      return querySnapshot.docs.map((doc) {
        return EmpresaModel.fromFirestore(doc.data(), doc.id);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // =========================================================================
  // --- FLUXO DE GERENCIAMENTO DE FERRAMENTAS/INSTRUMENTOS ---
  // =========================================================================

  /// Cadastra uma nova ferramenta atrelando-a ao domínio da empresa dona
  Future<bool> cadastrarNovoInstrumento({
    required String tipo,
    required String tag,
    required String numeroSerie,
    required String numeroCertificado,
    required String validade,
    required String emailUsuario, 
  }) async {
    try {
      String dominio = _extrairDominio(emailUsuario);
      if (dominio.isEmpty) return false;

      InstrumentoModel novoInstrumento = InstrumentoModel(
        tipo: tipo.trim(),
        tag: tag.toUpperCase().trim(),
        numeroSerie: numeroSerie.trim(),
        numeroCertificado: numeroCertificado.trim(),
        validade: validade.trim(),
        // Determina validade ao cadastrar comparando a data informada com a data atual
        estaValido: InstrumentoModel.validadeEhValida(validade.trim()),
        dominioEmpresa: dominio,
      );

      // Adiciona um documento com ID aleatório na coleção global 'ferramentas'
      await _firestore
          .collection('ferramentas')
          .add(novoInstrumento.toMap());

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Busca as ferramentas filtrando apenas pelo domínio da empresa do usuário logado.
  /// Graças ao motor do Firestore, se o usuário carregar essa lista uma vez com internet,
  /// ela ficará salva no aparelho e abrirá instantaneamente em campo (Modo Offline).
  Future<List<InstrumentoModel>> buscarInstrumentosPorEmpresa(String emailUsuario) async {
    try {
      String dominio = _extrairDominio(emailUsuario);
      
      final querySnapshot = await _firestore
          .collection('ferramentas')
          .where('dominio_empresa', isEqualTo: dominio)
          .get();

      return querySnapshot.docs.map((doc) {
        return InstrumentoModel.fromFirestore(doc.data(), doc.id);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Atualiza o certificado e validade de uma ferramenta pela TAG
  Future<bool> atualizarCertificadoPorTag({
    required String tag,
    required String novoCertificado,
    required String novaValidade,
  }) async {
    try {
      // Localiza o documento correspondente à TAG digitada/escaneada
      final query = await _firestore
          .collection('ferramentas')
          .where('tag', isEqualTo: tag.toUpperCase().trim())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        String docId = query.docs.first.id;
        
        final bool validadeOk = InstrumentoModel.validadeEhValida(novaValidade.trim());
        await _firestore.collection('ferramentas').doc(docId).update({
          'numeroCertificado': novoCertificado.trim(),
          'validade': novaValidade.trim(),
          'estaValido': validadeOk ? 1 : 0,
        });
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}