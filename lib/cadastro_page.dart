// lib/cadastro_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart'; // Importante para o PerfilUsuario

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
    // Escuta as mudanças nos campos de senha para atualizar a validação visual
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

  // Função que roda a cada letra digitada na senha
  void _validarSenha() {
    final senha = _senhaController.text;
    final confirma = _confirmaSenhaController.text;

    setState(() {
      _temMinimo8 = senha.length >= 8;
      _temMaiuscula = senha.contains(RegExp(r'[A-Z]'));
      _temMinuscula = senha.contains(RegExp(r'[a-z]'));
      _temEspecial = senha.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      _senhasIguais = senha.isNotEmpty && senha == confirma;
      
      // Validação geral rápida para liberar/bloquear o botão
      _formularioValido = _nomeController.text.isNotEmpty &&
          _cpfController.text.isNotEmpty &&
          _emailController.text.contains('@') &&
          _temMinimo8 && _temMaiuscula && _temMinuscula && _temEspecial &&
          _senhasIguais;
    });
  }

  void _salvarNovoUsuario() async {
    if (_formKey.currentState!.validate() && _formularioValido) {
      // Aqui você adicionaria no seu AuthService real no futuro
      bool salvoComSucesso = await _authService.cadastrarUsuarioNoBanco(
        nome: _nomeController.text,
        cpf: _cpfController.text,
        email: _emailController.text,
        senha: _senhaController.text,
        perfil: _perfilSelecionado,
    );
      if (!mounted) return;
      if (salvoComSucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuário registrado com sucesso no Banco de Dados!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Este e-mail já está cadastrado.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop(); // Retorna para a Home
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER (Mantendo a identidade visual) ---
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
                      Text('Olá, ${widget.nomeLogado}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Acesso: ${widget.perfilLogado.name.toUpperCase()}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            
            // --- FORMULÁRIO ROLÁVEL ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Form(
                  key: _formKey,
                  onChanged: _validarSenha, // Revalida ao digitar em qualquer campo
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Cadastrar Novo Usuário',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // 1. Nome Completo
                      TextFormField(
                        controller: _nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome Completo',
                          helperText: 'Apenas letras são permitidas neste campo.',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZÀ-ÿ\s]')), // Bloqueia números nativamente
                        ],
                        validator: (v) => v!.isEmpty ? 'Insira o nome completo' : null,
                      ),
                      const SizedBox(height: 16),

                      // 2. CPF
                      TextFormField(
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'CPF',
                          helperText: 'Preencha apenas com números.',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly, // Bloqueia letras nativamente
                          LengthLimitingTextInputFormatter(11),   // Limita ao tamanho do CPF
                        ],
                        validator: (v) => v!.length < 11 ? 'Insira um CPF válido (11 dígitos)' : null,
                      ),
                      const SizedBox(height: 16),

                      // 3. Status (Dropdown)
                      DropdownButtonFormField<PerfilUsuario>(
                        value: _perfilSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Status / Nível de Acesso',
                          prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: PerfilUsuario.operador, child: Text('Operador')),
                          DropdownMenuItem(value: PerfilUsuario.supervisor, child: Text('Supervisor')),
                        ],
                        onChanged: (PerfilUsuario? novoValor) {
                          if (novoValor != null) {
                            setState(() => _perfilSelecionado = novoValor);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // 4. E-mail
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          helperText: 'Necessário para recuperação de senha.',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || !v.contains('@') || !v.contains('.')) {
                            return 'Insira um e-mail válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 5. Senha
                      TextFormField(
                        controller: _senhaController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Indicadores de Senha Segura
                      Column(
                        children: [
                          _buildRequisitoItem('Mínimo de 8 caracteres', _temMinimo8),
                          _buildRequisitoItem('Pelo menos 1 letra maiúscula', _temMaiuscula),
                          _buildRequisitoItem('Pelo menos 1 letra minúscula', _temMinuscula),
                          _buildRequisitoItem('Pelo menos 1 caractere especial (!@#\$...)', _temEspecial),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 6. Confirmação da Senha
                      TextFormField(
                        controller: _confirmaSenhaController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirme a Senha',
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Indicador de senhas idênticas
                      _buildRequisitoItem(
                        _senhasIguais ? 'As senhas são idênticas' : 'As senhas precisam ser idênticas',
                        _senhasIguais,
                      ),
                      const SizedBox(height: 32),

                      // 7. Botão Criar Novo Usuário
                      ElevatedButton(
                        onPressed: _formularioValido ? _salvarNovoUsuario : null, // Desativa se inválido
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Criar Novo Usuário', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // --- 8. BOTÃO RETORNAR (Canto inferior direito) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(), // Voltar para a home
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

  // Widget auxiliar para renderizar as regrinhas com ícone de Certo/Aviso
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
              fontWeight: cumprido ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}