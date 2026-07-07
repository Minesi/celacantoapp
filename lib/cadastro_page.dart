// lib/cadastro_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart'; 
import 'usuario_model.dart'; // Importação do modelo estruturado do Firestore

class CadastroPage extends StatefulWidget {
  final PerfilUsuario perfilLogado;
  final String nomeLogado;
  final String emailLogado;

  const CadastroPage({
    super.key,
    required this.perfilLogado,
    required this.nomeLogado,
    required this.emailLogado,
  });

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmaSenhaController = TextEditingController();
  
  PerfilUsuario _perfilSelecionado = PerfilUsuario.operador; // Padrão inicial

  // Variáveis para validação em tempo real da senha
  bool _temMinimo8 = false;
  bool _temMaiuscula = false;
  bool _temMinuscula = false;
  bool _temEspecial = false;
  bool _senhasIguais = false;
  bool _formularioValido = false;

  @override
  void initState() {
    super.initState();
    // --- RESTRIÇÃO DE SEGURANÇA CRÍTICA ---
    // Impede que operadores acessem ou permaneçam nesta tela.
    if (widget.perfilLogado == PerfilUsuario.operador) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acesso negado: Operadores não têm permissão para cadastrar usuários.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop(); // Expulsa o usuário de volta para a tela anterior
      });
    }

    _senhaController.addListener(_validarSenha);
    _confirmaSenhaController.addListener(_validarSenha);
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmaSenhaController.dispose();
    super.dispose();
  }

  void _validarSenha() {
    final senha = _senhaController.text;
    final confirma = _confirmaSenhaController.text;

    setState(() {
      _temMinimo8 = senha.length >= 8;
      _temMaiuscula = senha.contains(RegExp(r'[A-Z]'));
      _temMinuscula = senha.contains(RegExp(r'[a-z]'));
      _temEspecial = senha.contains(RegExp(r'[!@#\$&*~•]'));
      _senhasIguais = senha.isNotEmpty && senha == confirma;

      _formularioValido = _temMinimo8 && _temMaiuscula && _temMinuscula && _temEspecial && _senhasIguais;
    });
  }

  void _submeterCadastro() async {
    if (_formKey.currentState!.validate() && _formularioValido) {
      // Exibe indicador visual de carregamento
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Executa a criação da conta passando os parâmetros individuais exigidos pelo seu AuthService
      bool sucesso = await _authService.cadastrarUsuario(
        nome: _nomeController.text.trim(),
        cpf: _cpfController.text.trim(),
        email: _emailController.text.trim(),
        perfil: _perfilSelecionado,
        senha: _senhaController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Fecha o modal de progresso

      if (sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usuário ${_nomeController.text} cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Limpa os campos para um próximo cadastro
        _nomeController.clear();
        _cpfController.clear();
        _emailController.clear();
        _senhaController.clear();
        _confirmaSenhaController.clear();
        setState(() {
          _perfilSelecionado = PerfilUsuario.operador;
          _validarSenha();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao cadastrar. Verifique se o e-mail já está em uso ou as regras de rede.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se for operador, renderiza um container vazio enquanto o Navigator.pop remove a tela do fluxo
    if (widget.perfilLogado == PerfilUsuario.operador) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Cadastrar Novo Usuário'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- 1. CAMPO NOME ---
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome Completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'Insira o nome completo' : null,
              ),
              const SizedBox(height: 16),

              // --- 2. CAMPO CPF ---
              TextFormField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'CPF',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'Insira o CPF' : null,
              ),
              const SizedBox(height: 16),

              // --- 3. CAMPO EMAIL ---
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail Corporativo',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Insira o e-mail';
                  if (!value.contains('@')) return 'Insira um e-mail válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- 4. SELEÇÃO DE PERFIL (Dropdown integrado ao Enum) ---
              DropdownButtonFormField<PerfilUsuario>(
                value: _perfilSelecionado,
                decoration: const InputDecoration(
                  labelText: 'Perfil de Acesso',
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                ),
                items: PerfilUsuario.values.map((PerfilUsuario perfil) {
                  return DropdownMenuItem<PerfilUsuario>(
                    value: perfil,
                    child: Text(perfil.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (PerfilUsuario? novoPerfil) {
                  if (novoPerfil != null) {
                    setState(() {
                      _perfilSelecionado = novoPerfil;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),

              // --- 5. CAMPO SENHA ---
              TextFormField(
                controller: _senhaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha Inicial',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),

              // --- 6. CAMPO CONFIRMAR SENHA ---
              TextFormField(
                controller: _confirmaSenhaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Senha',
                  prefixIcon: Icon(Icons.lock_clock_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // --- PAINEL DINÂMICO DE REQUISITOS DA SENHA ---
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A senha deve conter:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _buildRequisitoItem('No mínimo 8 caracteres', _temMinimo8),
                    _buildRequisitoItem('Pelo menos uma letra maiúscula', _temMaiuscula),
                    _buildRequisitoItem('Pelo menos uma letra minúscula', _temMinuscula),
                    _buildRequisitoItem('Pelo menos um caractere especial (!@#\$&*~)', _temEspecial),
                    _buildRequisitoItem('As senhas devem ser iguais', _senhasIguais),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- 7. BOTÃO DE ENVIO ---
              ElevatedButton(
                onPressed: _formularioValido ? _submeterCadastro : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cadastrar Usuário', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),

              // --- 8. BOTÃO RETORNAR ---
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 16, color: Colors.blue),
                    label: const Text('Retornar', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequisitoItem(String texto, bool cumprido) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            cumprido ? Icons.check_circle : Icons.radio_button_unchecked,
            color: cumprido ? Colors.green : Colors.grey[400],
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              color: cumprido ? Colors.green[700] : Colors.grey[600],
            ),
          ),
        ],
          ),
    );
  }
}