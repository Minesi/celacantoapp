// lib/editar_banco_dados_page.dart
import 'package:flutter/material.dart';
import 'auth_service.dart'; // Para reconhecer o PerfilUsuario
import 'database_helper.dart'; // Importando o seu banco de dados real

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

  // Lista dinâmica que será carregada do SQLite para alimentar o Dropdown
  List<Map<String, dynamic>> _listaUsuariosDB = [];

  // Controladores de Busca e Seleção
  final TextEditingController _buscaController = TextEditingController();
  Map<String, dynamic>? _usuarioSelecionado;

  // Controladores de texto para os campos editáveis da Planilha
  final TextEditingController _nomeEditController = TextEditingController();
  final TextEditingController _cpfEditController = TextEditingController();
  final TextEditingController _emailEditController = TextEditingController();
  final TextEditingController _senhaEditController = TextEditingController();
  PerfilUsuario? _perfilEditSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarTodosUsuarios(); // Carrega os usuários assim que a tela abre
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _nomeEditController.dispose();
    _cpfEditController.dispose();
    _emailEditController.dispose();
    _senhaEditController.dispose();
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

  // Preenche os campos de texto com os dados vindos do banco de dados
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

  // Faz o UPDATE real no arquivo usuarios_teste_v2.db
  Future<void> _salvarAlteracoesNoBanco() async {
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

              // --- CAMPO DE BUSCA UNIFICADO COM DROPDOWN REAL ---
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      decoration: InputDecoration(
                        labelText: 'Buscar usuário por nome',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (text) {
                        if (text.isNotEmpty) {
                          try {
                            final correspondencia = _listaUsuariosDB.firstWhere(
                              (user) => user['nome'].toString().toLowerCase() == text.toLowerCase().trim(),
                            );
                            _carregarDadosParaEdicao(correspondencia);
                          } catch (_) {
                            // Não faz nada caso ainda não ache correspondência perfeita digitando
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dropdown dinâmico alimentado pelo SQLite
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    height: 56, 
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.blue, size: 28),
                        hint: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('Lista'),
                        ),
                        items: _listaUsuariosDB.map((Map<String, dynamic> usuario) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: usuario,
                            child: Text(usuario['nome'] ?? ''),
                          );
                        }).toList(),
                        onChanged: (Map<String, dynamic>? novoUsuario) {
                          if (novoUsuario != null) {
                            _carregarDadosParaEdicao(novoUsuario);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- PLANILHA REAL DE ALTERAÇÃO DE DADOS ---
              Expanded(
                child: _usuarioSelecionado == null
                    ? Center(
                        child: Text(
                          'Busque ou selecione um usuário acima para editar.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 15),
                        ),
                      )
                    : SingleChildScrollView(
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
                                  // AJUSTE: Trocado 'value' por 'initialValue' e adicionado uma Key dinâmica baseada no usuário selecionado
                                  // Isso força o Flutter a reconstruir o dropdown corretamente quando o usuário muda na lista.
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

                                // --- AÇÕES DE SALVAR / EXCLUIR NO BANCO ---
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
                                )
                              ],
                            ),
                          ),
                        ),
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