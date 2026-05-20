// lib/perfil_page.dart
import 'package:flutter/material.dart';
import 'auth_service.dart';

class PerfilPage extends StatefulWidget {
  final PerfilUsuario perfilLogado;
  final String emailLogado;

  const PerfilPage({
    super.key,
    required this.perfilLogado,
    required this.emailLogado,
  });

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _senhaAtualController = TextEditingController();
  final _novaSenhaController = TextEditingController();

  // Controles de visibilidade das senhas (olhinho)
  bool _ocultarSenhaAtual = true;
  bool _ocultarNovaSenha = true;

  // Armazena os dados do usuário para não precisar rodar o FutureBuilder a cada clique
  Map<String, dynamic>? _dadosUsuario;
  bool _carregandoDados = true;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _senhaAtualController.dispose();
    _novaSenhaController.dispose();
    super.dispose();
  }

  // Carrega os dados do SQLite apenas UMA vez quando a tela abre
  void _carregarDadosIniciais() async {
    final dados = await _authService.buscarDadosUsuario(widget.emailLogado);
    setState(() {
      _dadosUsuario = dados;
      _carregandoDados = false;
    });
  }

  // Executa todas as validações de padrão de senha de uma vez só ao clicar no botão
  bool _validarPadraoNovaSenha(String senha) {
    bool temMinimo8 = senha.length >= 8;
    bool temMaiuscula = senha.contains(RegExp(r'[A-Z]'));
    bool temMinuscula = senha.contains(RegExp(r'[a-z]'));
    bool temEspecial = senha.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    return temMinimo8 && temMaiuscula && temMinuscula && temEspecial;
  }

  void _executarResetSenha() async {
    // 1. Valida se os campos não estão vazios
    if (!_formKey.currentState!.validate()) return;

    final senhaAtual = _senhaAtualController.text;
    final novaSenha = _novaSenhaController.text;

    // 2. Valida se a NOVA senha cumpre os requisitos de segurança
    if (!_validarPadraoNovaSenha(novaSenha)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A nova senha deve ter no mínimo 8 caracteres, contendo pelo menos 1 letra maiúscula, 1 minúscula e 1 caractere especial.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // 3. Se passou no padrão, tenta atualizar no banco de dados
    bool alteradoComSucesso = await _authService.atualizarSenha(
      emailUsuario: widget.emailLogado,
      senhaAtual: senhaAtual,
      novaSenha: novaSenha,
    );

    if (!mounted) return;

    if (alteradoComSucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senha atualizada com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      _senhaAtualController.clear();
      _novaSenhaController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: A "Senha Atual" informada está incorreta.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER (Mantendo o padrão de identidade visual) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.business, color: Colors.blue, size: 32),
                      SizedBox(width: 8),
                      Text('Empresa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Acesso: ${widget.perfilLogado.name.toUpperCase()}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // --- CORPO DA PÁGINA ---
            Expanded(
              child: _carregandoDados
                  ? const Center(child: CircularProgressIndicator())
                  : _dadosUsuario == null
                      ? const Center(child: Text('Erro ao carregar dados do usuário.'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Meu Perfil',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),

                                // Campos Informativos (Desativados/Somente Leitura)
                                TextFormField(
                                  initialValue: _dadosUsuario!['nome'],
                                  decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person)),
                                  enabled: false,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: _dadosUsuario!['cpf'],
                                  decoration: const InputDecoration(labelText: 'CPF', prefixIcon: Icon(Icons.badge)),
                                  enabled: false,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: _dadosUsuario!['email'],
                                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
                                  enabled: false,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: (_dadosUsuario!['perfil'] as String).toUpperCase(),
                                  decoration: const InputDecoration(labelText: 'Perfil de Acesso', prefixIcon: Icon(Icons.admin_panel_settings)),
                                  enabled: false,
                                ),
                                
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24.0),
                                  child: Divider(thickness: 1),
                                ),

                                const Text(
                                  'Alterar Senha do Sistema',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                                const SizedBox(height: 16),

                                // Campo: Senha Atual com Olhinho
                                TextFormField(
                                  controller: _senhaAtualController,
                                  obscureText: _ocultarSenhaAtual,
                                  decoration: InputDecoration(
                                    labelText: 'Senha Atual',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_ocultarSenhaAtual ? Icons.visibility_off : Icons.visibility),
                                      onPressed: () {
                                        setState(() {
                                          _ocultarSenhaAtual = !_ocultarSenhaAtual;
                                        });
                                      },
                                    ),
                                  ),
                                  validator: (v) => v!.isEmpty ? 'Insira a sua senha atual' : null,
                                ),
                                const SizedBox(height: 16),

                                // Campo: Nova Senha com Olhinho
                                TextFormField(
                                  controller: _novaSenhaController,
                                  obscureText: _ocultarNovaSenha,
                                  decoration: InputDecoration(
                                    labelText: 'Nova Senha',
                                    prefixIcon: const Icon(Icons.lock_reset),
                                    suffixIcon: IconButton(
                                      icon: Icon(_ocultarNovaSenha ? Icons.visibility_off : Icons.visibility),
                                      onPressed: () {
                                        setState(() {
                                          _ocultarNovaSenha = !_ocultarNovaSenha;
                                        });
                                      },
                                    ),
                                  ),
                                  validator: (v) => v!.isEmpty ? 'Insira a nova senha' : null,
                                ),
                                const SizedBox(height: 12),

                                // Informativo fixo das regras (Não atualiza ao digitar, fica estático e limpo)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.withOpacity(0.15)),
                                  ),
                                  child: const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Padrões obrigatórios para a Nova Senha:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                                      ),
                                      SizedBox(height: 6),
                                      Text('• Mínimo de 8 caracteres', style: TextStyle(fontSize: 12, color: Colors.black)),
                                      Text('• Pelo menos 1 letra maiúscula', style: TextStyle(fontSize: 12, color: Colors.black87)),
                                      Text('• Pelo menos 1 letra minúscula', style: TextStyle(fontSize: 12, color: Colors.black87)),
                                      Text('• Pelo menos 1 caractere especial (!@#\$%^&*)', style: TextStyle(fontSize: 12, color: Colors.black87)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Botão Reset de Senha (Sempre ativo, valida no clique)
                                ElevatedButton(
                                  onPressed: _executarResetSenha,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Reset de Senha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
            ),

            // --- HEADER DE RETORNO (Canto inferior direito) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 16, color: Colors.blue),
                    label: const Text('Retornar', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}