// lib/gestao_ferramentas_page.dart
import 'package:flutter/material.dart';
import 'empresa_service.dart';
import 'instrumento_model.dart';

class GestaoFerramentasPage extends StatefulWidget {
  // ADICIONADO: Passando o e-mail do usuário logado para isolamento de dados corporativos
  final String emailLogado;

  const GestaoFerramentasPage({
    super.key, 
    required this.emailLogado,
  });

  @override
  State<GestaoFerramentasPage> createState() => _GestaoFerramentasPageState();
}

class _GestaoFerramentasPageState extends State<GestaoFerramentasPage> {
  final EmpresaService _service = EmpresaService();
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
    _carregarFerramentas();
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

  /// CORRIGIDO: Agora chama o método certo passando o e-mail do usuário
  Future<void> _carregarFerramentas() async {
    setState(() => _carregando = true);
    final ferramentas = await _service.buscarInstrumentosPorEmpresa(widget.emailLogado);
    setState(() {
      _listaFerramentas = ferramentas;
      _carregando = false;
    });
  }

  /// CORRIGIDO: Novo método de inserção integrado ao Cloud Firestore
  Future<void> _adicionarFerramenta() async {
    if (_formKeyAdd.currentState!.validate()) {
      bool sucesso = await _service.cadastrarNovoInstrumento(
        tipo: _tipoController.text,
        tag: _tagController.text,
        numeroSerie: _serieController.text,
        numeroCertificado: _certController.text,
        validade: _validadeController.text,
        emailUsuario: widget.emailLogado, // Passa o e-mail para capturar o domínio corporativo
      );

      if (mounted) {
        if (sucesso) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Equipamento cadastrado com sucesso!')),
          );
          _tipoController.clear();
          _tagController.clear();
          _serieController.clear();
          _certController.clear();
          _validadeController.clear();
          _carregarFerramentas(); // Recarrega a lista da empresa
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao cadastrar equipamento.')),
          );
        }
      }
    }
  }

  /// CORRIGIDO: Novo método de atualização unificado
  Future<void> _atualizarCertificado() async {
    if (_tagSelecionadaParaAtualizar == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma TAG válida.')),
      );
      return;
    }

    if (_formKeyUpdate.currentState!.validate()) {
      bool sucesso = await _service.atualizarCertificadoPorTag(
        tag: _tagSelecionadaParaAtualizar!,
        novoCertificado: _novoCertController.text,
        novaValidade: _novaValidadeController.text,
      );

      if (mounted) {
        if (sucesso) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Certificado atualizado com sucesso!')),
          );
          _novoCertController.clear();
          _novaValidadeController.clear();
          setState(() => _tagSelecionadaParaAtualizar = null);
          _carregarFerramentas(); // Atualiza a visualização
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao atualizar ativo.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestão de Ferramentas e Calibrações')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ferramentas Cadastradas da Empresa',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _listaFerramentas.isEmpty
                      ? const Text('Nenhuma ferramenta localizada para o seu domínio.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _listaFerramentas.length,
                          itemBuilder: (context, index) {
                            final f = _listaFerramentas[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(Icons.build, color: f.estaValido ? Colors.green : Colors.red),
                                title: Text('${f.tag} - ${f.tipo}'),
                                subtitle: Text('Série: ${f.numeroSerie} | Certificado: ${f.numeroCertificado}\nValidade: ${f.validade}'),
                                trailing: Icon(
                                  f.estaValido ? Icons.check_circle : Icons.warning,
                                  color: f.estaValido ? Colors.green : Colors.red,
                                ),
                              ),
                            );
                          },
                        ),
                  const Divider(height: 40),
                  _buildFormAdicionar(),
                  const Divider(height: 40),
                  _buildFormAtualizar(),
                ],
              ),
            ),
    );
  }

  Widget _buildFormAdicionar() {
    return Form(
      key: _formKeyAdd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cadastrar Novo Ativo / Equipamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tipoController,
            decoration: const InputDecoration(labelText: 'Tipo do Equipamento (Ex: Anemômetro)', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tagController,
            decoration: const InputDecoration(labelText: 'TAG Identificadora (Ex: ANE-005)', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _serieController,
            decoration: const InputDecoration(labelText: 'Número de Série', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _certController,
            decoration: const InputDecoration(labelText: 'Número do Certificado de Calibração', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _validadeController,
            decoration: const InputDecoration(labelText: 'Validade do Certificado (MM/AAAA)', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _adicionarFerramenta,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Center(child: Text('Salvar Equipamento')),
          ),
        ],
      ),
    );
  }

  Widget _buildFormAtualizar() {
    return Form(
      key: _formKeyUpdate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Renovação de Certificado de Calibração', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tagSelecionadaParaAtualizar,
            hint: const Text('Selecione a TAG do equipamento'),
            decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
            items: _listaFerramentas.map((f) => DropdownMenuItem(value: f.tag, child: Text('${f.tag} - ${f.tipo}'))).toList(),
            onChanged: (val) => setState(() => _tagSelecionadaParaAtualizar = val),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _novoCertController,
            decoration: const InputDecoration(labelText: 'Novo Número do Certificado', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _novaValidadeController,
            decoration: const InputDecoration(labelText: 'Nova Validade (MM/AAAA)', border: OutlineInputBorder()),
            validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _atualizarCertificado,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Center(child: Text('Atualizar Ativo')),
          ),
        ],
      ),
    );
  }
}