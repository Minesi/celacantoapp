// lib/main.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Importa o openDatabase global
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'home_page.dart';

final AuthService _authService = AuthService();

void main() async {
  // CRUCIAL: Garante que os canais de plataforma nativos estejam vinculados ao motor C++
  // antes de qualquer inicialização ou registro de plugin, sanando o erro de Isolate no Windows.
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true, // Garante que os dados fiquem salvos no disco
    cacheSizeBytes: -1, // Cache sem limite rígido
  );
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbHelper = DatabaseHelper();
  await dbHelper.sincronizarProjetosPendentes();
  
  runApp(const MyApp());
  await FirebaseFirestore.instance.collection('testes').add({
    'plataforma': 'Executando com sucesso!',
    'horario': DateTime.now().toString(),
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Celacantoapp Login',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[100],
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailRecuperacaoController = TextEditingController(); // Novo controlador para recuperação
  
  bool _obscurePassword = true;
  bool _modoRecuperacao = false; // Define se exibe o Login ou a Recuperação

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailRecuperacaoController.dispose();
    super.dispose();
  }

  void _submitLogin() async {
    if (_formKey.currentState!.validate()) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      UsuarioLogado? perfilLogado = await _authService.loginLocal(
        _emailController.text,
        _passwordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Fecha o carregamento

      if (perfilLogado != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              perfil: perfilLogado.perfil,
              nomeUsuario: perfilLogado.nome,
              emailUsuario: _emailController.text,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-mail ou senha incorretos.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Função atualizada para processar o pedido real de redefinição via Firebase Auth
  void _submitRecuperacao() async {
    if (_formKey.currentState!.validate()) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final email = _emailRecuperacaoController.text.trim();
      
      // Realiza a chamada direta para o envio do e-mail do Firebase Auth
      bool enviado = await _authService.enviarEmailRecuperacao(email);

      if (!mounted) return;
      Navigator.of(context).pop(); // Fecha o carregamento

      if (enviado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('E-mail de recuperação enviado para $email com sucesso! Verifique sua caixa de entrada.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        
        _emailRecuperacaoController.clear();
        setState(() {
          _modoRecuperacao = false; // Retorna automaticamente para a tela de login
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Não foi possível enviar o e-mail. Verifique se o e-mail está cadastrado e correto.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/logo.png', height: 100),
                  const SizedBox(height: 16),
                  
                  // Título dinâmico baseado no modo atual
                  Text(
                    _modoRecuperacao ? 'Recuperar Senha' : 'Bem-vindo de volta',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Alternância de layouts usando condicionais de árvore de Widgets do Dart
                  if (!_modoRecuperacao) ...[
                    // --- LAYOUT DO LOGIN TRADICIONAL ---
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail ou Usuário',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira seu e-mail ou usuário';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira sua senha';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // Altera o estado do formulário para exibir o modo de recuperação
                          setState(() {
                            _modoRecuperacao = true;
                          });
                        },
                        child: const Text(
                          'Esqueceu a senha?',
                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitLogin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Entrar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    // --- LAYOUT DE RECUPERAÇÃO DE SENHA ---
                    const Text(
                      'Digite seu email para recuperar a senha',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailRecuperacaoController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, digite o e-mail de cadastro';
                        }
                        if (!value.contains('@')) {
                          return 'Insira um formato de e-mail válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitRecuperacao,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Recuperar Senha',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _modoRecuperacao = false;
                        });
                      },
                      child: const Text(
                        'Voltar para o Login',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}