// lib/editar_banco_dados_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';

class EditarBancoDadosPage extends StatefulWidget {
  final PerfilUsuario perfilLogado;
  final String nomeLogado;

  const EditarBancoDadosPage({
    super.key,
    required this.perfilLogado,
    required this.nomeLogado,
  });

  @override
  State<EditarBancoDadosPage> createState() => _EditarBancoDadosPageState();
}

class _EditarBancoDadosPageState extends State<EditarBancoDadosPage> {
  // Instância do seu gerenciador do banco usuarios_teste_v2.db
  final DatabaseHelper _dbHelper = DatabaseHelper();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _listaUsuariosDB = [];
  List<Map<String, dynamic>> _listaEmpresasDB = [];

  final TextEditingController _buscaController = TextEditingController();
  Map<String, dynamic>? _usuarioSelecionado;
  Map<String, dynamic>? _empresaSelecionada;
  String _modoEdicao = 'usuarios';

  // Controladores de texto para os campos editáveis da Planilha
  final TextEditingController _nomeEditController = TextEditingController();
  final TextEditingController _cpfEditController = TextEditingController();
  final TextEditingController _emailEditController = TextEditingController();
  final TextEditingController _senhaEditController = TextEditingController();
  final TextEditingController _cnpjEditController = TextEditingController();
  final TextEditingController _razaoSocialEditController = TextEditingController();
  final TextEditingController _nomeFantasiaEditController = TextEditingController();
  final TextEditingController _dominioEditController = TextEditingController();
  PerfilUsuario? _perfilEditSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarTodosUsuarios();
    _carregarTodasEmpresas();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _nomeEditController.dispose();
    _cpfEditController.dispose();
    _emailEditController.dispose();
    _senhaEditController.dispose();
    _cnpjEditController.dispose();
    _razaoSocialEditController.dispose();
    _nomeFantasiaEditController.dispose();
    _dominioEditController.dispose();
    super.dispose();
  }

  // Busca a lista atualizada direto do SQLite para o Dropdown
  Future<void> _carregarTodosUsuarios() async {
    final usuarios = await _dbHelper.getUsuarios();
    if (!mounted) return;
    setState(() {
      _listaUsuariosDB = usuarios;
    });
  }

  Future<void> _carregarTodasEmpresas() async {
    final empresas = await _dbHelper.getEmpresas();
    if (!mounted) return;
    setState(() {
      _listaEmpresasDB = empresas;
    });
  }

  void _carregarDadosParaEdicao(Map<String, dynamic> usuario) {
    setState(() {
      _usuarioSelecionado = usuario;
      _buscaController.text = usuario['nome'] ?? '';
      _nomeEditController.text = usuario['nome'] ?? '';
      _cpfEditController.text = usuario['cpf'] ?? '';
      _emailEditController.text = usuario['email'] ?? '';
      _senhaEditController.text = usuario['senha'] ?? '';
      
      // Tratamento para converter a String do banco de volta para o Enum
      _perfilEditSelecionado = PerfilUsuario.values.firstWhere(
        (p) => p.name == usuario['perfil'],
        orElse: () => PerfilUsuario.operador,
      );
    });
  }

  void _carregarEmpresaParaEdicao(Map<String, dynamic> empresa) {
    setState(() {
      _empresaSelecionada = empresa;
      _cnpjEditController.text = empresa['cnpj']?.toString() ?? '';
      _razaoSocialEditController.text = empresa['razaoSocial']?.toString() ?? '';
      _nomeFantasiaEditController.text = empresa['nomeFantasia']?.toString() ?? '';
      _dominioEditController.text = empresa['dominio_empresa']?.toString() ?? '';
    });
  }

  Future<void> _salvarAlteracoesNoBanco() async {
    if (_modoEdicao == 'empresas' && _empresaSelecionada != null) {
      final dadosAtualizados = {
        'cnpj': _cnpjEditController.text.trim(),
        'razaoSocial': _razaoSocialEditController.text.trim(),
        'nomeFantasia': _nomeFantasiaEditController.text.trim(),
        'dominio_empresa': _dominioEditController.text.trim().toLowerCase(),
      };

      await _dbHelper.insertEmpresa(dadosAtualizados);
      await _carregarTodasEmpresas();
      await _firestore.collection('empresas').doc(_dominioEditController.text.trim().toLowerCase()).set({
        'cnpj': _cnpjEditController.text.trim(),
        'razao_social': _razaoSocialEditController.text.trim(),
        'nome_fantasia': _nomeFantasiaEditController.text.trim(),
        'dominio': _dominioEditController.text.trim().toLowerCase(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa atualizada com sucesso!'), backgroundColor: Colors.green),
      );
      return;
    }

    if (_usuarioSelecionado != null) {
      Map<String, dynamic> dadosAtualizados = {
        'id': _usuarioSelecionado!['id'],
        'nome': _nomeEditController.text.trim(),
        'cpf': _cpfEditController.text.trim(),
        'email': _emailEditController.text.trim(),
        'senha': _senhaEditController.text.trim(),
        'perfil': _perfilEditSelecionado!.name,
      };

      await _dbHelper.updateUsuario(dadosAtualizados);
      await _carregarTodosUsuarios();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados atualizados no banco com sucesso!'), backgroundColor: Colors.green),
      );
    }
  }

  // Faz o DELETE real no arquivo usuarios_teste_v2.db
  Future<void> _confirmarExclusaoNoBanco() async {
    if (_usuarioSelecionado != null) {
      int idUsuario = _usuarioSelecionado!['id'];
      
      // 1. Executa os processos assíncronos primeiro
      await _dbHelper.deleteUsuario(idUsuario);
      await _carregarTodosUsuarios(); 

      // 2. Garante que a tela ainda está ativa após TODOS os awaits terminarem
      if (!mounted) return;

      // 3. Atualiza o estado da tela com segurança
      setState(() {
        _usuarioSelecionado = null;
        _buscaController.clear();
      });
      
      // 4. Executa as chamadas visuais usando o BuildContext de forma 100% segura
      Navigator.of(context).pop(); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário removido permanentemente do banco.'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Abre a janela de confirmação de exclusão
  void _mostrarDialogExclusao() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Atenção!'),
            ],
          ),
          content: Text(
            'Tem certeza que deseja excluir os dados de "${_usuarioSelecionado?['nome']}"?\n\nEsta é uma ação irreversível no banco de dados.',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: _confirmarExclusaoNoBanco,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir do Banco', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50]!,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.grey[800]),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- CABEÇALHO PADRÃO DO SISTEMA ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo.png', height: 40),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Olá, ${widget.nomeLogado}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Acesso: ${widget.perfilLogado.name.toUpperCase()}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                'Painel Administrativo do Banco de Dados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      decoration: InputDecoration(
                        labelText: _modoEdicao == 'empresas' ? 'Buscar empresa por nome' : 'Buscar usuário por nome',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (text) {
                        if (text.isEmpty) return;
                        if (_modoEdicao == 'empresas') {
                          final correspondencia = _listaEmpresasDB.where((empresa) {
                            final nome = (empresa['nomeFantasia'] ?? '').toString().toLowerCase();
                            return nome.contains(text.toLowerCase().trim());
                          }).toList();
                          if (correspondencia.isNotEmpty) {
                            _carregarEmpresaParaEdicao(correspondencia.first);
                          }
                          return;
                        }
                        try {
                          final correspondencia = _listaUsuariosDB.firstWhere(
                            (user) => user['nome'].toString().toLowerCase() == text.toLowerCase().trim(),
                          );
                          _carregarDadosParaEdicao(correspondencia);
                        } catch (_) {}
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    height: 56,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _modoEdicao,
                        icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.blue, size: 28),
                        items: const [
                          DropdownMenuItem(value: 'usuarios', child: Text('Usuários')),
                          DropdownMenuItem(value: 'empresas', child: Text('Empresas')),
                        ],
                        onChanged: (valor) {
                          if (valor == null) return;
                          setState(() {
                            _modoEdicao = valor;
                            _usuarioSelecionado = null;
                            _empresaSelecionada = null;
                            _buscaController.clear();
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Expanded(
                child: _modoEdicao == 'empresas'
                    ? (_empresaSelecionada == null
                        ? Center(
                            child: Text(
                              'Busque ou selecione uma empresa acima para editar.',
                              style: TextStyle(color: Colors.grey[500], fontSize: 15),
                            ),
                          )
                        : _buildEditorEmpresas())
                    : (_usuarioSelecionado == null
                        ? Center(
                            child: Text(
                              'Busque ou selecione um usuário acima para editar.',
                              style: TextStyle(color: Colors.grey[500], fontSize: 15),
                            ),
                          )
                        : _buildEditorUsuarios()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorUsuarios() {
    return SingleChildScrollView(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Planilha de Edição Cadastral (Banco de Dados)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey),
              ),
              const Divider(height: 20),
              _buildPlanilhaRow('NOME:', TextField(controller: _nomeEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('CPF:', TextField(controller: _cpfEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('EMAIL:', TextField(controller: _emailEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('SENHA:', TextField(controller: _senhaEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow(
                'PERFIL:',
                DropdownButtonFormField<PerfilUsuario>(
                  key: ValueKey(_usuarioSelecionado!['id']),
                  initialValue: _perfilEditSelecionado,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  items: PerfilUsuario.values.map((PerfilUsuario p) {
                    return DropdownMenuItem<PerfilUsuario>(
                      value: p,
                      child: Text(p.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _perfilEditSelecionado = val),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mostrarDialogExclusao,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('Excluir Registro', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _salvarAlteracoesNoBanco,
                      icon: const Icon(Icons.save_as_rounded),
                      label: const Text('Salvar Alterações'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorEmpresas() {
    return SingleChildScrollView(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Planilha de Edição de Empresas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey),
              ),
              const Divider(height: 20),
              _buildPlanilhaRow('CNPJ:', TextField(controller: _cnpjEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('RAZÃO SOCIAL:', TextField(controller: _razaoSocialEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('NOME FANTASIA:', TextField(controller: _nomeFantasiaEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 12),
              _buildPlanilhaRow('DOMÍNIO:', TextField(controller: _dominioEditController, decoration: const InputDecoration(isDense: true))),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _salvarAlteracoesNoBanco,
                icon: const Icon(Icons.save_as_rounded),
                label: const Text('Salvar Alterações da Empresa'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanilhaRow(String label, Widget inputWidget) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: inputWidget,
          ),
        ),
      ],
    );
  }
}