// lib/novo_projeto_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'empresa_model.dart';
import 'empresa_service.dart';
import 'qr_code_scanner_page.dart'; 
import 'captura_ocr_page.dart';
import 'instrumento_model.dart';
import 'projeto_model.dart';
import 'leitura_model.dart';
import 'relatorio_service.dart';
import 'database_helper.dart';
import 'auth_service.dart';

class NovoProjetoPage extends StatefulWidget {
  final String emailLogado;

  const NovoProjetoPage({
    super.key,
    required this.emailLogado,
  });

  @override
  State<NovoProjetoPage> createState() => _NovoProjetoPageState();
}

class _NovoProjetoPageState extends State<NovoProjetoPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  
  int _etapaAtual = 1; 
  bool _carregandoEmpresas = true;

  String _cnpjSelecionadoParaProjeto = '';
  EmpresaModel? _empresaSelecionadaDadosObjeto;

  String? _projetoSelecionado;

  // Definição dos Escopos e Suas Ferramentas Conforme Requisito 8
  final Map<String, List<String>> _escoposETestes = {
    'Fluxo Laminar': ['Balômetro', 'Manômetro', 'Anemômetro', 'Fotômetro', 'Termohigrometro', 'Decibelímetro', 'Luxímetro'],
    'Ar Comprimido': ['Ponto de Orvalho', 'Contador de Partículas', 'Amostrador de ar', 'Análises de Óleo e Gases Cromatógrafo', 'Decibelímetro', 'Luxímetro'],
    'Cabine de Exaustão': ['Termohigrometro', 'Anemômetro', 'Decibelímetro', 'Luxímetro', 'Termoanemômetro'],
    'HVAC': ['Balômetro', 'Manômetro', 'Anemômetro', 'Fotômetro', 'Termohigrometro', 'Contador de Partículas', 'Decibelímetro', 'Luxímetro'],
    'Teste': ['Manômetro'],
  };

  // Mapeamento de Prefixos Aceitos por Tipo de Campo (Requisito 1 & 6)
  final Map<String, String> _prefixosPorTipo = {
    'Balômetro': 'BAL',
    'Manômetro': 'MAN',
    'Anemômetro': 'ANE',
    'Fotômetro': 'FOT',
    'Termohigrometro': 'TER',
    'Decibelímetro': 'DEC',
    'Luxímetro': 'LUX',
    'Ponto de Orvalho': 'PNT',
    'Contador de Partículas': 'PAR',
    'Amostrador de ar': 'AMO',
    'Análises de Óleo e Gases Cromatógrafo': 'CRO',
    'Termoanemômetro': 'TAN',
  };

  List<String> _ferramentasRequeridasAtuais = [];
  
  // Armazena as ferramentas validadas com sucesso para o ProjetoModel (Requisito 7)
  final Map<String, InstrumentoModel> _ferramentasEscaneadasSucesso = {};
  
  // Lista que armazenará os dados capturados via OCR dos displays pós-ferramentas
  final List<LeituraModel> _leiturasCapturadasOcr = [];

  // Controladores para o modal rápido de cadastro de nova empresa
  final _formKeyEmpresaRapida = GlobalKey<FormState>();
  final _cnpjRapidoController = TextEditingController();
  final _razaoSocialRapidoController = TextEditingController();
  final _nomeFantasiaRapidoController = TextEditingController();

  List<EmpresaModel> _listaEmpresasDisponiveisMenu = [];

  @override
  void initState() {
    super.initState();
    _carregarEmpresasCadastradas();
  }

  @override
  void dispose() {
    _cnpjRapidoController.dispose();
    _razaoSocialRapidoController.dispose();
    _nomeFantasiaRapidoController.dispose();
    super.dispose();
  }

  Future<void> _carregarEmpresasCadastradas() async {
    setState(() => _carregandoEmpresas = true);
    try {
      final mapasLocais = await _dbHelper.getEmpresas();
      
      setState(() {
        // CORREÇÃO: Mapeamento manual para contornar a ausência do EmpresaModel.fromMap
        _listaEmpresasDisponiveisMenu = mapasLocais.map((m) {
          return EmpresaModel(
            cnpj: m['cnpj']?.toString() ?? '',
            razaoSocial: m['razaoSocial']?.toString() ?? '',
            nomeFantasia: m['nomeFantasia']?.toString() ?? '',
            dominio: m['dominio_empresa']?.toString() ?? '',
          );
        }).toList();
        _carregandoEmpresas = false;
      });
    } catch (e) {
      setState(() => _carregandoEmpresas = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar empresas locais: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Lógica híbrida interna/externa de processamento e validação de TAG
  Future<void> _processarValidacaoFerramenta(String tipoFerramenta, String tagDigitadaOuEscaneada) async {
    final tagFormatada = tagDigitadaOuEscaneada.trim().toUpperCase();
    final prefixoEsperado = _prefixosPorTipo[tipoFerramenta] ?? '';

    if (prefixoEsperado.isNotEmpty && !tagFormatada.startsWith(prefixoEsperado)) {
      _exibirAlertaAviso('TAG Inválida', 'O campo de "$tipoFerramenta" aceita apenas instrumentos com o prefixo "$prefixoEsperado" (Ex: $prefixoEsperado-011).');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    InstrumentoModel? instrumentoEncontrado;

    try {
      final db = await _dbHelper.database;
      final localRes = await db.query('instrumentos', where: 'tag = ?', whereArgs: [tagFormatada], limit: 1);

      if (localRes.isNotEmpty) {
        final dadosUsuario = await _authService.buscarDadosUsuario(widget.emailLogado);
        final dominio = dadosUsuario?['dominio_empresa'] ?? '';
        
        instrumentoEncontrado = InstrumentoModel(
          id: localRes.first['id']?.toString() ?? '',
          tipo: localRes.first['tipo']?.toString() ?? tipoFerramenta,
          tag: localRes.first['tag']?.toString() ?? tagFormatada,
          numeroSerie: localRes.first['numeroSerie']?.toString() ?? 'S/N',
          numeroCertificado: localRes.first['numeroCertificado']?.toString() ?? 'N/A',
          validade: localRes.first['validade']?.toString() ?? '01/2000',
          // Determina validade sempre comparando com a data atual, não apenas pelo flag salvo
          estaValido: InstrumentoModel.validadeEhValida(localRes.first['validade']?.toString() ?? ''),
          dominioEmpresa: dominio,
        );
      } else {
        final nuvemRes = await _firestore
            .collection('instrumentos')
            .where('tag', isEqualTo: tagFormatada)
            .limit(1)
            .get();

        if (nuvemRes.docs.isNotEmpty) {
          instrumentoEncontrado = InstrumentoModel.fromFirestore(nuvemRes.docs.first.data(), nuvemRes.docs.first.id);
        }
      }
    } catch (e) {
      debugPrint("Erro na varredura dos bancos: $e");
    }

    if (!mounted) return;
    Navigator.of(context).pop(); 

    if (instrumentoEncontrado == null) {
      _exibirAlertaAviso('Não Encontrado', 'A ferramenta com a TAG "$tagFormatada" não está cadastrada em nosso banco interno ou nuvem.');
      return;
    }

    bool dataValida = InstrumentoModel.validadeEhValida(instrumentoEncontrado.validade);

    if (dataValida) {
      setState(() {
        _ferramentasEscaneadasSucesso[tipoFerramenta] = instrumentoEncontrado!;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$tipoFerramenta ($tagFormatada) validado com sucesso!'), backgroundColor: Colors.green),
      );
    } else {
      _solicitarLiberacaoSupervisor(tipoFerramenta, instrumentoEncontrado);
    }
  }

  void _solicitarLiberacaoSupervisor(String tipoFerramenta, InstrumentoModel instrumento) {
    final emailSupController = TextEditingController();
    final senhaSupController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber),
              SizedBox(width: 8),
              Text('Validade Expirada', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A ferramenta ${instrumento.tag} está com a calibração vencida (${instrumento.validade}).\n\nInsira as credenciais de um Supervisor para autorizar o uso especial:'),
              const SizedBox(height: 16),
              TextField(
                controller: emailSupController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail do Supervisor', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: senhaSupController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha de Liberação', prefixIcon: Icon(Icons.lock)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(child: CircularProgressIndicator()),
                );

                Map<String, dynamic>? dadosSup = await _authService.buscarDadosUsuario(emailSupController.text.trim());
                
                if (dadosSup != null && (dadosSup['perfil'] == 'supervisor' || dadosSup['perfil'] == 'admin')) {
                  if (!mounted) return;
                  Navigator.of(context).pop(); 
                  Navigator.of(context).pop(); 

                  setState(() {
                    _ferramentasEscaneadasSucesso[tipoFerramenta] = instrumento;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Uso de ${instrumento.tag} liberado pelo Supervisor!'), backgroundColor: Colors.orange),
                  );
                } else {
                  if (!mounted) return;
                  Navigator.of(context).pop(); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Credenciais inválidas ou usuário sem nível de Supervisor!'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
              child: const Text('Autorizar Uso', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _abrirScannerQrParaFerramenta(String tipoFerramenta) async {
    final resultadoQr = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrCodeScannerPage()),
    );

    if (resultadoQr != null && resultadoQr.isNotEmpty) {
      _processarValidacaoFerramenta(tipoFerramenta, resultadoQr);
    }
  }

  void _abrirDigitacaoManualFerramenta(String tipoFerramenta) {
    final manualController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Digitar TAG para $tipoFerramenta'),
          content: TextField(
            controller: manualController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Ex: ${_prefixosPorTipo[tipoFerramenta] ?? 'TAG'}-001',
              prefixIcon: const Icon(Icons.keyboard),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (manualController.text.isNotEmpty) {
                  _processarValidacaoFerramenta(tipoFerramenta, manualController.text);
                }
              },
              child: const Text('Validar'),
            )
          ],
        );
      },
    );
  }

  void _dispararLeituraOcrDisplay(String tipoFerramentaVinculada) async {
    final textoExtraidoOcr = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const CapturaOcrPage()),
    );

    if (textoExtraidoOcr != null && textoExtraidoOcr.isNotEmpty) {
      final instrumentoVinculado = _ferramentasEscaneadasSucesso[tipoFerramentaVinculada];
      final tagCodigoFerramenta = instrumentoVinculado?.tag ?? 'N/A';

      setState(() {
        _leiturasCapturadasOcr.add(LeituraModel(
          equipamento: tipoFerramentaVinculada,
          codigoFerramenta: tagCodigoFerramenta,
          valorCapturado: textoExtraidoOcr, 
          dataHoraCaptura: DateTime.now(),
        ));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Display de $tipoFerramentaVinculada anexado via OCR!'), backgroundColor: Colors.green),
      );
    }
  }

  void _criarProjetoFinal() async {
    if (_empresaSelecionadaDadosObjeto == null || _projetoSelecionado == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final idUnicoProjeto = 'PRJ-${DateTime.now().millisecondsSinceEpoch}';
    
    final novoProjetoCompletoObjeto = ProjetoModel(
      id: idUnicoProjeto,
      cnpjEmpresa: _empresaSelecionadaDadosObjeto!.cnpj,
      tipoProjeto: _projetoSelecionado!,
      ferramentasRequeridas: _ferramentasRequeridasAtuais,
      ferramentasEscaneadas: Map<String, InstrumentoModel>.from(_ferramentasEscaneadasSucesso),
      leiturasOcr: List<LeituraModel>.from(_leiturasCapturadasOcr),
    );

    try {
      final mapaProjeto = {
        'id': novoProjetoCompletoObjeto.id,
        'cnpjEmpresa': novoProjetoCompletoObjeto.cnpjEmpresa,
        'tipoProjeto': novoProjetoCompletoObjeto.tipoProjeto,
        'ferramentasRequeridas': novoProjetoCompletoObjeto.ferramentasRequeridas,
        'ferramentasEscaneadas': novoProjetoCompletoObjeto.ferramentasEscaneadas.map((k, v) => MapEntry(k, v.toMap())),
        'leiturasOcr': novoProjetoCompletoObjeto.leiturasOcr.map((l) => l.toMap()).toList(),
        'dataCriacao': DateTime.now().toIso8601String(),
        'operadorResponsavel': widget.emailLogado,
      };

      await _firestore.collection('projetos').doc(idUnicoProjeto).set(mapaProjeto);

      // CORREÇÃO: Sincronização exata com a assinatura real do seu RelatorioService
      final relatorioService = RelatorioService();
      final templatePath = relatorioService.assetPathParaProjeto(_projetoSelecionado!);
      await relatorioService.gerarRelatorioProjeto(
        projeto: novoProjetoCompletoObjeto,
        nomeEmpresa: _empresaSelecionadaDadosObjeto!.nomeFantasia,
        assetTemplatePath: templatePath,
      );

      final projetoMapaLocal = {
        'id': novoProjetoCompletoObjeto.id,
        'cnpjEmpresa': novoProjetoCompletoObjeto.cnpjEmpresa,
        'tipoProjeto': novoProjetoCompletoObjeto.tipoProjeto,
        'ferramentasRequeridas': novoProjetoCompletoObjeto.ferramentasRequeridas,
        'ferramentasEscaneadas': novoProjetoCompletoObjeto.ferramentasEscaneadas.map((k, v) => MapEntry(k, v.toMap())),
        'leiturasOcr': novoProjetoCompletoObjeto.leiturasOcr.map((l) => l.toMap()).toList(),
        'dataCriacao': DateTime.now().toIso8601String(),
        'operadorResponsavel': widget.emailLogado,
        'templateUtilizado': templatePath,
      };

      await _dbHelper.insertProjeto(projetoMapaLocal);

      if (!mounted) return;
      Navigator.of(context).pop(); 

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Projeto $idUnicoProjeto gerado com sucesso!'), backgroundColor: Colors.green),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao registrar projeto e gerar Word: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _exibirAlertaAviso(String titulo, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  void _salvarNovaEmpresaRapido() async {
  if (_formKeyEmpresaRapida.currentState!.validate()) {
    final novaEmpresa = EmpresaModel(
      cnpj: _cnpjRapidoController.text.trim(),
      razaoSocial: _razaoSocialRapidoController.text.trim(),
      nomeFantasia: _nomeFantasiaRapidoController.text.trim(),
      dominio: _authService.extrairDominio(widget.emailLogado), 
    );

    // CORREÇÃO: Criamos um mapa limpo apenas com tipos primitivos que o SQLite aceita
    final mapaSqliteLimpo = {
      'cnpj': novaEmpresa.cnpj,
      'razaoSocial': novaEmpresa.razaoSocial,
      'nomeFantasia': novaEmpresa.nomeFantasia,
      'dominio_empresa': novaEmpresa.dominio,
    };

    // Salva localmente sem passar listas vazias []
    int resultadoLocal = await _dbHelper.insertEmpresa(mapaSqliteLimpo);

    if (resultadoLocal > 0) {
      if (!mounted) return;
      Navigator.of(context).pop(); 

      try {
        // Para a nuvem (Firebase), mapeamos exatamente conforme a estrutura existente que você mostrou
        final mapaFirebase = {
          'cnpj': novaEmpresa.cnpj,
          'razao_social': novaEmpresa.razaoSocial,
          'nome_fantasia': novaEmpresa.nomeFantasia,
          'dominio': novaEmpresa.dominio,
          'projetosFinais': [],  // Mantém a lista vazia inicial padrão do seu banco
          'projetosModelo': [],  // Mantém a lista vazia inicial padrão do seu banco
        };

        await _firestore.collection('empresas').doc(novaEmpresa.cnpj).set(mapaFirebase);
      } catch (e) {
        debugPrint("Guardado offline no Firestore/Falha ao enviar: $e");
      }

      _cnpjRapidoController.clear();
      _razaoSocialRapidoController.clear();
      _nomeFantasiaRapidoController.clear();
      _carregarEmpresasCadastradas();
    }
  }
}

  void _abrirFormularioModalEmpresaRapida() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
          child: Form(
            key: _formKeyEmpresaRapida,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Cadastrar Nova Empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cnpjRapidoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CNPJ da Empresa', prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Insira o CNPJ' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _razaoSocialRapidoController,
                    decoration: const InputDecoration(labelText: 'Razão Social', prefixIcon: Icon(Icons.business_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Insira a Razão Social' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nomeFantasiaRapidoController,
                    decoration: const InputDecoration(labelText: 'Nome Fantasia', prefixIcon: Icon(Icons.storefront_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Insira o Nome Fantasia' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _salvarNovaEmpresaRapido,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Salvar Empresa', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Novo Projeto Operacional'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildToggleBotaotapa('1. Configuração', _etapaAtual == 1, () => setState(() => _etapaAtual = 1)),
                const Icon(Icons.chevron_right, color: Colors.white60),
                _buildToggleBotaotapa('2. Ferramental & Display', _etapaAtual == 2, () {
                  if (_empresaSelecionadaDadosObjeto != null && _projetoSelecionado != null) {
                    setState(() => _etapaAtual = 2);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecione a empresa e o tipo de projeto primeiro!'), backgroundColor: Colors.amber),
                    );
                  }
                }),
              ],
            ),
          ),
          Expanded(
            child: _carregandoEmpresas 
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _etapaAtual == 1 ? _buildPainelEtapa1() : _buildPainelEtapa2(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBotaotapa(String label, bool ativo, VoidCallback acao) {
    return TextButton(
      onPressed: acao,
      child: Text(
        label,
        style: TextStyle(color: ativo ? Colors.white : Colors.white60, fontWeight: ativo ? FontWeight.bold : FontWeight.normal, fontSize: 14),
      ),
    );
  }

  Widget _buildPainelEtapa1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Selecione a Empresa Cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            TextButton.icon(
              onPressed: _abrirFormularioModalEmpresaRapida,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nova Empresa'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _cnpjSelecionadoParaProjeto.isEmpty ? null : _cnpjSelecionadoParaProjeto,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.business_center_outlined), hintText: 'Clique para escolher a empresa'),
          items: _listaEmpresasDisponiveisMenu.map((empresa) {
            return DropdownMenuItem<String>(value: empresa.cnpj, child: Text(empresa.nomeFantasia));
          }).toList(),
          onChanged: (String? novoCnpj) {
            if (novoCnpj != null) {
              setState(() {
                _cnpjSelecionadoParaProjeto = novoCnpj;
                _empresaSelecionadaDadosObjeto = _listaEmpresasDisponiveisMenu.firstWhere((e) => e.cnpj == novoCnpj);
              });
            }
          },
        ),
        const SizedBox(height: 24),
        const Text('Tipo de Ensaio / Escopo Regulatório', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _projetoSelecionado,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.assignment_outlined), hintText: 'Selecione a natureza do escopo'),
          items: _escoposETestes.keys.map((tipo) {
            return DropdownMenuItem<String>(value: tipo, child: Text(tipo));
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _projetoSelecionado = v;
                _ferramentasRequeridasAtuais = _escoposETestes[v] ?? [];
                _ferramentasEscaneadasSucesso.clear();
              });
            }
          },
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: (_empresaSelecionadaDadosObjeto != null && _projetoSelecionado != null)
              ? () => setState(() => _etapaAtual = 2)
              : null,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blue),
          child: const Text('Avançar para Ferramental', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        )
      ],
    );
  }

  Widget _buildPainelEtapa2() {
    bool todasValidadas = _ferramentasEscaneadasSucesso.length == _ferramentasRequeridasAtuais.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Validação Obrigatória para: $_projetoSelecionado',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _ferramentasRequeridasAtuais.length,
          itemBuilder: (context, index) {
            final tipoFerramenta = _ferramentasRequeridasAtuais[index];
            final ins = _ferramentasEscaneadasSucesso[tipoFerramenta];
            final escaneado = ins != null;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              color: escaneado ? Colors.green[50] : Colors.white,
              child: ListTile(
                leading: Icon(escaneado ? Icons.check_circle : Icons.radio_button_unchecked, color: escaneado ? Colors.green : Colors.grey),
                title: Text(tipoFerramenta, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: escaneado 
                    ? Text('TAG: ${ins.tag} | Certificado: ${ins.numeroCertificado}\nValidade: ${ins.validade}', style: const TextStyle(fontSize: 12))
                    : Text('Prefixo exigido: ${_prefixosPorTipo[tipoFerramenta]}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                      onPressed: () => _abrirScannerQrParaFerramenta(tipoFerramenta),
                      tooltip: 'Escanear QR (Apenas TAG)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard, color: Colors.blueGrey),
                      onPressed: () => _abrirDigitacaoManualFerramenta(tipoFerramenta),
                      tooltip: 'Digitar TAG Manualmente',
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        
        const Text('Leituras dos Displays (OCR)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _ferramentasEscaneadasSucesso.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Valide as ferramentas primeiro para liberar as leituras OCR de display.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ferramentasEscaneadasSucesso.keys.length,
                itemBuilder: (context, idx) {
                  final tipoFerramenta = _ferramentasEscaneadasSucesso.keys.elementAt(idx);
                  
                  final leituraExistente = _leiturasCapturadasOcr.any((l) => l.equipamento == tipoFerramenta)
                      ? _leiturasCapturadasOcr.firstWhere((l) => l.equipamento == tipoFerramenta)
                      : null;

                  return Card(
                    color: leituraExistente != null ? Colors.blue[50] : Colors.grey[100],
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(Icons.document_scanner, color: leituraExistente != null ? Colors.blue : Colors.grey),
                      title: Text('Display de $tipoFerramenta'),
                      subtitle: leituraExistente != null 
                          ? Text('Valor Capturado: ${leituraExistente.valorCapturado}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))
                          : const Text('Nenhuma captura realizada ainda.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: ElevatedButton.icon(
                        onPressed: () => _dispararLeituraOcrDisplay(tipoFerramenta),
                        icon: const Icon(Icons.camera_alt, size: 14),
                        label: Text(leituraExistente != null ? 'Re-capturar' : 'Capturar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: leituraExistente != null ? Colors.grey : Colors.blueGrey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                        ),
                      ),
                    ),
                  );
                },
              ),

        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: todasValidadas && _leiturasCapturadasOcr.length == _ferramentasRequeridasAtuais.length ? _criarProjetoFinal : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[350],
          ),
          child: const Text('Finalizar e Emitir Relatório Word', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}