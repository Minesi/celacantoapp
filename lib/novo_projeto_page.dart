// lib/novo_projeto_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Adicionado para gerenciar transações de projetos
import 'empresa_model.dart';
import 'empresa_service.dart';
import 'qr_code_scanner_page.dart'; 
import 'captura_ocr_page.dart';
import 'instrumento_model.dart';
import 'projeto_model.dart';
import 'leitura_model.dart';
import 'relatorio_service.dart';

class NovoProjetoPage extends StatefulWidget {
  // ADICIONADO: Exige o e-mail logado para isolamento do domínio e cache offline
  final String emailLogado;

  const NovoProjetoPage({
    super.key,
    required this.emailLogado,
  });

  @override
  State<NovoProjetoPage> createState() => _NovoProjetoPageState();
}

class _NovoProjetoPageState extends State<NovoProjetoPage> {
  final EmpresaService _empresaService = EmpresaService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância direta para persistência de projetos
  
  int _etapaAtual = 1; 
  final List<bool> _selecaoAbas = [true, false];
  bool _carregandoEmpresas = true;

  String _cnpjSelecionadoParaProjeto = '';
  String _nomeEmpresaSelecionadaParaProjeto = '';

  final _formKeyNovoCliente = GlobalKey<FormState>();
  final _controllerRazaoSocial = TextEditingController();
  final _controllerNomeFantasia = TextEditingController();
  final _controllerCnpjNovo = TextEditingController();

  List<EmpresaModel> _listaEmpresasDisponiveis = [];

  // Dados do Fluxo de Escopo Técnico
  String? _projetoSelecionado;
  final List<String> _tiposDeProjetosValidos = [
    'Qualificação Térmica de Autoclave',
    'Mapeamento Térmica de Depósito',
    'Certificação de Fluxo Laminar',
    'Validação de Sistema HVAC',
    'Validação Técnico (Modo Teste)'
  ];

  Map<String, String> _mapeamentoFerramentasNecessarias = {};
  Map<String, InstrumentoModel> _ferramentasEscaneadasSucesso = {};

  @override
  void initState() {
    super.initState();
    _buscarClientesDisponiveis();
  }

  @override
  void dispose() {
    _controllerRazaoSocial.dispose();
    _controllerNomeFantasia.dispose();
    _controllerCnpjNovo.dispose();
    super.dispose();
  }

  /// Recupera as empresas (Usa cache local se estiver offline automaticamente)
  Future<void> _buscarClientesDisponiveis() async {
    setState(() => _carregandoEmpresas = true);
    final empresas = await _empresaService.buscarTodasEmpresas();
    setState(() {
      _listaEmpresasDisponiveis = empresas;
      _carregandoEmpresas = false;
    });
  }

  /// CORRIGIDO: Chama o método unificado do Firestore passando o e-mail
  Future<void> _salvarNovoClienteNoDB() async {
    if (_formKeyNovoCliente.currentState!.validate()) {
      bool sucesso = await _empresaService.salvarNovaEmpresa(
        razaoSocial: _controllerRazaoSocial.text,
        nomeFantasia: _controllerNomeFantasia.text,
        cnpj: _controllerCnpjNovo.text,
        emailResponsavel: widget.emailLogado,
      );

      if (mounted) {
        if (sucesso) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cliente/Empresa salva com sucesso!')),
          );
          _controllerRazaoSocial.clear();
          _controllerNomeFantasia.clear();
          _controllerCnpjNovo.clear();
          _buscarClientesDisponiveis(); 
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao salvar cliente corporativo.')),
          );
        }
      }
    }
  }

  void _selecionarEmpresaParaProjeto(EmpresaModel empresa) {
    setState(() {
      _cnpjSelecionadoParaProjeto = empresa.cnpj;
      _nomeEmpresaSelecionadaParaProjeto = empresa.nomeFantasia.isNotEmpty ? empresa.nomeFantasia : empresa.razaoSocial;
      _etapaAtual = 2; 
    });
  }

  void _atualizarEscopoEAtivosNecessarios(String? escopo) {
    if (escopo == null) return;

    Map<String, String> ferramentas = {};
    if (escopo == 'Qualificação Térmica de Autoclave') {
      ferramentas = {'Sensor de Temperatura Padrão': '', 'Manômetro de Pressão Absoluta': ''};
    } else if (escopo == 'Mapeamento Térmica de Depósito') {
      ferramentas = {'Data Logger de Temperatura': '', 'Termohigrómetro Estacionário': ''};
    } else if (escopo == 'Certificação de Fluxo Laminar') {
      ferramentas = {'Anemômetro de Fio Quente': '', 'Contador de Partículas': ''};
    } else if (escopo == 'Validação de Sistema HVAC') {
      ferramentas = {'Balômetro de Vazão': '', 'Manômetro Diferencial': '', 'Termohigrómetro Portátil': ''};
    } else if (escopo == 'Validação Técnico (Modo Teste)') {
      ferramentas = {'Manômetro Diferencial': '', 'Anemômetro': ''};
    }

    setState(() {
      _projetoSelecionado = escopo;
      _mapeamentoFerramentasNecessarias = ferramentas;
      _ferramentasEscaneadasSucesso.clear();
    });
  }

  /// CORRIGIDO: Método de busca de instrumento via TAG diretamente do Firestore (com suporte a cache)
  Future<void> _abrirEscanerDeAtivo(String nomeFerramenta) async {
    final String? tagEscaneada = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrCodeScannerPage()),
    );

    if (tagEscaneada == null || tagEscaneada.trim().isEmpty) return;

    setState(() => _carregandoEmpresas = true);

    try {
      // Faz uma busca direta na coleção de ferramentas filtrando pela TAG escaneada
      final querySnapshot = await _firestore
          .collection('ferramentas')
          .where('tag', isEqualTo: tagEscaneada.toUpperCase().trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final instrumento = InstrumentoModel.fromFirestore(doc.data(), doc.id);

        setState(() {
          _ferramentasEscaneadasSucesso[nomeFerramenta] = instrumento;
          _mapeamentoFerramentasNecessarias[nomeFerramenta] = instrumento.tag;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ativo ${instrumento.tag} vinculado com sucesso!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aviso: TAG não localizada ou fora do domínio corporativo.')),
          );
        }
      }
    } catch (_) {
      // Fallback amigável
    } finally {
      setState(() => _carregandoEmpresas = false);
    }
  }

  /// CORRIGIDO: Criação e salvamento do projeto final
  Future<void> _criarProjetoFinal() async {
    if (_projetoSelecionado == null) return;

    // Garante identificador estável para o documento
    String idUnicoProjeto = 'PRJ_${_cnpjSelecionadoParaProjeto}_${DateTime.now().millisecondsSinceEpoch}';

    ProjetoModel novoProjeto = ProjetoModel(
      id: idUnicoProjeto,
      cnpjEmpresa: _cnpjSelecionadoParaProjeto,
      tipoProjeto: _projetoSelecionado!,
      ferramentasRequeridas: _mapeamentoFerramentasNecessarias.keys.toList(),
      ferramentasEscaneadas: _ferramentasEscaneadasSucesso,
      leiturasOcr: [],
    );

    try {
      // Mapeamento limpo para o Firestore
      Map<String, dynamic> dadosProjeto = {
        'id': novoProjeto.id,
        'cnpjEmpresa': novoProjeto.cnpjEmpresa,
        'tipoProjeto': novoProjeto.tipoProjeto,
        'ferramentasRequeridas': novoProjeto.ferramentasRequeridas,
        'dominio_empresa': widget.emailLogado.split('@').last.toLowerCase().trim(),
        'ferramentasEscaneadas': novoProjeto.ferramentasEscaneadas.map((key, value) => MapEntry(key, value.toMap())),
        'dataCriacao': FieldValue.serverTimestamp(),
      };

      // Grava no Firestore (Suporta enfileiramento offline nativo no dispositivo)
      await _firestore.collection('projetos').doc(idUnicoProjeto).set(dadosProjeto);

      if (!mounted) return;

      if (_projetoSelecionado == 'Validação Técnico (Modo Teste)') {
        // Fluxo de teste abre diretamente a tela do OCR
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CapturaOcrPage(
              idProjeto: novoProjeto.id,
              tipoProjeto: novoProjeto.tipoProjeto,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Projeto cadastrado e sincronizado com sucesso!')),
        );
        Navigator.pop(context); // Retorna para a HomePage
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao registrar escopo técnico.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abertura de Escopo Técnico')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _etapaAtual == 1 ? _buildEtapaSelecaoEmpresa() : _buildEtapaConfiguracaoEscopo(),
      ),
    );
  }

  Widget _buildEtapaSelecaoEmpresa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ToggleButtons(
            isSelected: _selecaoAbas,
            onPressed: (index) {
              setState(() {
                for (int i = 0; i < _selecaoAbas.length; i++) {
                  _selecaoAbas[i] = i == index;
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minHeight: 40, minWidth: 160),
            children: const [Text('Selecionar Cliente'), Text('Novo Cliente (Instalação)')],
          ),
        ),
        const SizedBox(height: 20),
        if (_selecaoAbas[0]) ...[
          const Text('Clientes Cadastrados no Sistema:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _carregandoEmpresas
              ? const Center(child: CircularProgressIndicator())
              : Expanded(
                  child: _listaEmpresasDisponiveis.isEmpty
                      ? const Center(child: Text('Nenhum cliente localizado no domínio corporativo.'))
                      : ListView.builder(
                          itemCount: _listaEmpresasDisponiveis.length,
                          itemBuilder: (context, index) {
                            final emp = _listaEmpresasDisponiveis[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.business, color: Colors.blue),
                                title: Text(emp.razaoSocial, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('CNPJ: ${emp.cnpj} | Fantasia: ${emp.nomeFantasia}'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () => _selecionarEmpresaParaProjeto(emp),
                              ),
                            );
                          },
                        ),
                ),
        ] else ...[
          Expanded(
            child: SingleChildScrollView(
              child: Form(
                key: _formKeyNovoCliente,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cadastrar Nova Organização', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _controllerRazaoSocial,
                      decoration: const InputDecoration(labelText: 'Razão Social', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _controllerNomeFantasia,
                      decoration: const InputDecoration(labelText: 'Nome Fantasia', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _controllerCnpjNovo,
                      decoration: const InputDecoration(labelText: 'CNPJ (Somente Números)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) => v == null || v.trim().length < 14 ? 'CNPJ Inválido' : null,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _salvarNovoClienteNoDB,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Center(child: Text('Adicionar Empresa')),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ],
    );
  }

  Widget _buildEtapaConfiguracaoEscopo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _etapaAtual = 1)),
            Expanded(child: Text('Cliente: $_nomeEmpresaSelecionadaParaProjeto', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _projetoSelecionado,
          hint: const Text('Selecione o Escopo/Projeto Técnico'),
          decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.assignment)),
          items: _tiposDeProjetosValidos.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: _atualizarEscopoEAtivosNecessarios,
        ),
        const SizedBox(height: 20),
        if (_projetoSelecionado != null) ...[
          const Text('Vincular Ativos Requeridos (Escaneie o QR Code):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _mapeamentoFerramentasNecessarias.length,
              itemBuilder: (context, index) {
                String ferramenta = _mapeamentoFerramentasNecessarias.keys.elementAt(index);
                String tagVinculada = _mapeamentoFerramentasNecessarias[ferramenta]!;
                bool escaneado = tagVinculada.isNotEmpty;

                return Card(
                  color: escaneado ? Colors.green[50] : Colors.amber[50],
                  child: ListTile(
                    leading: Icon(escaneado ? Icons.qr_code_scanner : Icons.qr_code, color: escaneado ? Colors.green : Colors.amber[800]),
                    title: Text(ferramenta, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(escaneado ? 'TAG Vinculada: $tagVinculada' : 'Pendente de leitura da TAG'),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _abrirEscanerDeAtivo(ferramenta),
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: Text(escaneado ? 'Trocar' : 'Ler QR'),
                      style: ElevatedButton.styleFrom(backgroundColor: escaneado ? Colors.grey : Colors.blue, foregroundColor: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text('Escolha um tipo de projeto para listar as ferramentas necessárias.'))),

        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _projetoSelecionado != null && _ferramentasEscaneadasSucesso.length == _mapeamentoFerramentasNecessarias.length ? _criarProjetoFinal : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _projetoSelecionado == 'Validação Técnico (Modo Teste)' ? Colors.amber[900] : Colors.green[700],
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[350],
            disabledForegroundColor: Colors.grey[600],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _projetoSelecionado == 'Validação Técnico (Modo Teste)' 
                ? 'Concluir Teste e Emitir Word' 
                : 'Criar Projeto', 
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
          ),
        ),
      ],
    );
  }
}