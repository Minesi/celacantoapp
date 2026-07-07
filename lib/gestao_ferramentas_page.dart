// lib/gestao_ferramentas_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';
import 'auth_service.dart';
import 'instrumento_model.dart';

class GestaoFerramentasPage extends StatefulWidget {
  final String emailLogado;

  const GestaoFerramentasPage({
    super.key, 
    required this.emailLogado,
  });

  @override
  State<GestaoFerramentasPage> createState() => _GestaoFerramentasPageState();
}

class _GestaoFerramentasPageState extends State<GestaoFerramentasPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  List<InstrumentoModel> _listaFerramentas = [];
  bool _carregando = true;

  // Controllers para Nova Ferramenta
  final _formKeyAdd = GlobalKey<FormState>();
  final _tipoController = TextEditingController();
  final _tagController = TextEditingController();
  final _serieController = TextEditingController();
  final _certController = TextEditingController();
  final _validadeController = TextEditingController();

  // Campos para Atualizar Certificado
  final _formKeyUpdate = GlobalKey<FormState>();
  String? _tagSelecionadaParaAtualizar;
  final _novoCertController = TextEditingController();
  final _novaValidadeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sincronizarECarregarFerramentas();
  }

  @override
  void dispose() {
    _tipoController.dispose();
    _tagController.dispose();
    _serieController.dispose();
    _certController.dispose();
    _validadeController.dispose();
    _novoCertController.dispose();
    _novaValidadeController.dispose();
    super.dispose();
  }

  /// Carrega as ferramentas locais e tenta atualizar com dados da Nuvem de forma resiliente
  Future<void> _sincronizarECarregarFerramentas() async {
    setState(() => _carregando = true);
    final dominio = _authService.extrairDominio(widget.emailLogado);

    try {
      // 1. Carrega o Cache Local (SQLite) primeiro para resposta visual imediata
      final dadosLocais = await _dbHelper.getInstrumentos();
      setState(() {
        _listaFerramentas = dadosLocais.map((map) {
          return InstrumentoModel(
            id: map['id']?.toString() ?? '',
            tipo: map['tipo']?.toString() ?? '',
            tag: map['tag']?.toString() ?? '',
            numeroSerie: map['numeroSerie']?.toString() ?? '',
            numeroCertificado: map['numeroCertificado']?.toString() ?? '',
            validade: map['validade']?.toString() ?? '',
            estaValido: map['estaValido'] == 1,
            dominioEmpresa: map['dominio_empresa']?.toString() ?? dominio,
          );
        }).where((element) => element.dominioEmpresa == dominio).toList();
      });

      // 2. Tenta buscar atualizações na nuvem (Firestore) filtrando pelo domínio
      final snapshotNuvem = await _firestore
          .collection('instrumentos')
          .where('dominio_empresa', isEqualTo: dominio)
          .get();

      if (snapshotNuvem.docs.isNotEmpty) {
        List<InstrumentoModel> ferramentasNuvem = [];
        
        for (final doc in snapshotNuvem.docs) {
          final inst = InstrumentoModel.fromFirestore(doc.data(), doc.id);
          ferramentasNuvem.add(inst);
          // Atualiza/Salva no cache local para manter offline sincronizado
          await _dbHelper.insertInstrumento(inst.toMap());
        }

        setState(() {
          _listaFerramentas = ferramentasNuvem;
        });
      }
    } catch (e) {
      debugPrint("Modo Offline Ativo ou erro de sincronização: $e");
    } finally {
      setState(() => _carregando = false);
    }
  }

  /// Adiciona uma ferramenta localmente e na Nuvem
  void _adicionarFerramenta() async {
    if (!_formKeyAdd.currentState!.validate()) return;

    final dominio = _authService.extrairDominio(widget.emailLogado);
    final tagFormatada = _tagController.text.trim().toUpperCase();
    final idGerado = 'INST-${DateTime.now().millisecondsSinceEpoch}';

    final novoInstrumento = InstrumentoModel(
      id: idGerado,
      tipo: _tipoController.text.trim(),
      tag: tagFormatada,
      numeroSerie: _serieController.text.trim(),
      numeroCertificado: _certController.text.trim(),
      validade: _validadeController.text.trim(),
      estaValido: true,
      dominioEmpresa: dominio,
    );

    // 1. Persistência Local (SQLite)
    int localResult = await _dbHelper.insertInstrumento(novoInstrumento.toMap());

    if (localResult > 0) {
      try {
        // 2. Sincronização na Nuvem (Firestore)
        await _firestore.collection('instrumentos').doc(tagFormatada).set(novoInstrumento.toMap());
      } catch (e) {
        debugPrint("Ferramenta salva offline. Sincronização pendente: $e");
      }

      // Limpa formulário e recarrega visual
      _tipoController.clear();
      _tagController.clear();
      _serieController.clear();
      _certController.clear();
      _validadeController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ativo $tagFormatada cadastrado com sucesso!'), backgroundColor: Colors.green),
      );
      _sincronizarECarregarFerramentas();
    }
  }

  /// Atualiza o certificado e validade de uma ferramenta existente
  void _atualizarCertificado() async {
    if (!_formKeyUpdate.currentState!.validate() || _tagSelecionadaParaAtualizar == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione uma TAG válida.'), backgroundColor: Colors.amber),
      );
      return;
    }

    final tagAlvo = _tagSelecionadaParaAtualizar!;
    final novoCertificado = _novoCertController.text.trim();
    final novaValidade = _novaValidadeController.text.trim();

    final dadosAtualizadosSqlite = {
      'numeroCertificado': novoCertificado,
      'validade': novaValidade,
      'estaValido': 1,
    };

    // 1. Atualização Local (SQLite)
    int localResult = await _dbHelper.updateInstrumentoPorTag(tagAlvo, dadosAtualizadosSqlite);

    if (localResult > 0) {
      try {
        // 2. Atualização na Nuvem (Firestore usando merge para não deletar os outros campos)
        await _firestore.collection('instrumentos').doc(tagAlvo).set({
          'numeroCertificado': novoCertificado,
          'validade': novaValidade,
          'estaValido': 1,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Atualização salva em cache offline: $e");
      }

      _novoCertController.clear();
      _novaValidadeController.clear();
      setState(() => _tagSelecionadaParaAtualizar = null);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calibração da TAG $tagAlvo atualizada com sucesso!'), backgroundColor: Colors.green),
      );
      _sincronizarECarregarFerramentas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Gestão de Ativos & Ferramental'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCardCadastro(),
                  const SizedBox(height: 24),
                  _buildCardAtualizacao(),
                  const SizedBox(height: 24),
                  _buildSeccaoListaVisual(),
                ],
              ),
            ),
    );
  }

  Widget _buildCardCadastro() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKeyAdd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cadastrar Nova Ferramenta Padrão', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tipoController,
                decoration: const InputDecoration(labelText: 'Tipo do Instrumento (Ex: Manômetro)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.construction)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o tipo' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'TAG Única (Ex: MAN-011)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira a TAG' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serieController,
                decoration: const InputDecoration(labelText: 'Número de Série', border: OutlineInputBorder(), prefixIcon: Icon(Icons.fingerprint)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o número de série' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _certController,
                decoration: const InputDecoration(labelText: 'Nº Certificado / Licença de Calibração', border: OutlineInputBorder(), prefixIcon: Icon(Icons.gavel)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o certificado' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _validadeController,
                decoration: const InputDecoration(labelText: 'Validade da Calibração (MM/AAAA)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira a validade' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _adicionarFerramenta,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Center(child: Text('Registrar Ativo no Sistema', style: TextStyle(fontWeight: FontWeight.bold))),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardAtualizacao() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKeyUpdate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Renovação de Calibração / Certificado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _tagSelecionadaParaAtualizar,
                hint: const Text('Selecione a TAG do equipamento'),
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
                items: _listaFerramentas.map((f) {
                  return DropdownMenuItem(value: f.tag, child: Text('${f.tag} - ${f.tipo}'));
                }).toList(),
                onChanged: (val) => setState(() => _tagSelecionadaParaAtualizar = val),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _novoCertController,
                decoration: const InputDecoration(labelText: 'Novo Número do Certificado', border: OutlineInputBorder(), prefixIcon: Icon(Icons.gavel)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _novaValidadeController,
                decoration: const InputDecoration(labelText: 'Nova Validade (MM/AAAA)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _atualizarCertificado,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Center(child: Text('Atualizar Dados de Calibração', style: TextStyle(fontWeight: FontWeight.bold))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeccaoListaVisual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Ativos Cadastrados no seu Domínio (${_listaFerramentas.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        _listaFerramentas.isEmpty
            ? const Card(child: ListTile(title: Text('Nenhum ativo localizado para o seu domínio organizacional.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _listaFerramentas.length,
                itemBuilder: (context, index) {
                  final f = _listaFerramentas[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.handyman, color: Colors.blue[800])),
                      title: Text('${f.tag} — ${f.tipo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Série: ${f.numeroSerie} | Certificado: ${f.numeroCertificado}\nValidade: ${f.validade}', style: const TextStyle(fontSize: 12)),
                      trailing: Icon(Icons.check_circle, color: f.estaValido ? Colors.green : Colors.grey),
                    ),
                  );
                },
              ),
      ],
    );
  }
}