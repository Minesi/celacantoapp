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
  final _confirmaNovaSenhaController = TextEditingController(); // Adicionado para validação

  // Controles de visibilidade das senhas (olhinho)
  bool _ocultarSenhaAtual = true;
  bool _ocultarNovaSenha = true;
  bool _ocultarConfirmaNovaSenha = true;

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
    _confirmaNovaSenhaController.dispose();
    super.dispose();
  }

  void _carregarDadosIniciais() async {
    // Busca os dados do utilizador usando o e-mail passado pelo construtor
    final dados = await _authService.buscarDadosUsuario(widget.emailLogado);
    if (!mounted) return;
    setState(() {
      _dadosUsuario = dados;
      _carregandoDados = false;
    });
  }

  void _executarAlteracaoSenha() async {
    if (_formKey.currentState!.validate()) {
      // Mostra indicador de carregamento
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      bool sucesso = await _authService.atualizarSenha(
        emailUsuario: widget.emailLogado,
        senhaAtual: _senhaAtualController.text,
        novaSenha: _novaSenhaController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Fecha o carregamento

      if (sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Senha alterada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        // Limpa os campos após o sucesso
        _senhaAtualController.clear();
        _novaSenhaController.clear();
        _confirmaNovaSenhaController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao alterar a senha. Verifique a sua senha atual.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: _carregandoDados
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- INFORMAÇÕES DO UTILIZADOR ---
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nome: ${_dadosUsuario?['nome'] ?? 'Não informado'}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text('E-mail: ${widget.emailLogado}'),
                              const SizedBox(height: 8),
                              Text('Perfil: ${widget.perfilLogado.name.toUpperCase()}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // --- FORMULÁRIO DE ALTERAÇÃO DE SENHA ---
                      const Text(
                        'Alterar Senha de Acesso',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 16),

                      // Campo: Senha Atual
                      TextFormField(
                        controller: _senhaAtualController,
                        obscureText: _ocultarSenhaAtual,
                        decoration: InputDecoration(
                          labelText: 'Senha Atual',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_ocultarSenhaAtual ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _ocultarSenhaAtual = !_ocultarSenhaAtual),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira a sua senha atual';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo: Nova Senha
                      TextFormField(
                        controller: _novaSenhaController,
                        obscureText: _ocultarNovaSenha,
                        decoration: InputDecoration(
                          labelText: 'Nova Senha',
                          prefixIcon: const Icon(Icons.lock_reset),
                          suffixIcon: IconButton(
                            icon: Icon(_ocultarNovaSenha ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _ocultarNovaSenha = !_ocultarNovaSenha),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira a nova senha';
                          }
                          if (value.length < 6) {
                            return 'A nova senha deve ter pelo menos 6 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo: Confirmar Nova Senha
                      TextFormField(
                        controller: _confirmaNovaSenhaController,
                        obscureText: _ocultarConfirmaNovaSenha,
                        decoration: InputDecoration(
                          labelText: 'Confirmar Nova Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_ocultarConfirmaNovaSenha ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _ocultarConfirmaNovaSenha = !_ocultarConfirmaNovaSenha),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, confirme a nova senha';
                          }
                          if (value != _novaSenhaController.text) {
                            return 'As senhas não coincidem';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Botão de Execução
                      ElevatedButton(
                        onPressed: _executarAlteracaoSenha,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Atualizar Senha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}