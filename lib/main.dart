import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart'; // Importa o openDatabase global
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'auth_service.dart';
import 'home_page.dart';
// sugestão de código para lib/main.dart
final AuthService _authService = AuthService();
void main() {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MyApp());
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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

 void _submitLogin() async {
  if (_formKey.currentState!.validate()) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // 1. O aplicativo aguarda a resposta do banco aqui...
    UsuarioLogado? perfilLogado = await _authService.loginLocal(
      _emailController.text,
      _passwordController.text,
    );

    // ==========================================
    // 2. A TRAVA DE SEGURANÇA (CORREÇÃO AQUI):
    // Se a tela foi fechada durante a espera, cancela o resto do código
    if (!mounted) return;
    // ==========================================

    // Como passamos pela trava, agora é 100% seguro usar o context!
    Navigator.of(context).pop(); // Fecha o carregamento

    if (perfilLogado != null) {
      // Navega para a HomePage passando as informações coletadas
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
      // Se falhar, mostra o erro na tela
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-mail ou senha incorretos.'),
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
                children: [Image.asset('assets/images/logo.png', height: 100),
                  const SizedBox(height: 16),
                  const Text(
                    'Bem-vindo de volta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 2. Campo de Login / Email
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

                  // 3. Campo de Senha
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword 
                              ? Icons.visibility_off 
                              : Icons.visibility,
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
                      if (value.length < 8) {
                        return 'A senha deve ter pelo menos 8 caracteres';
                      }
                      return null;
                    },
                  ),
                  
                  // 4. Opção de Recuperar Senha
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // Navegação para tela de recuperação
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ir para Recuperação de Senha')),
                        );
                      },
                      child: const Text(
                        'Esqueceu a senha?',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Button de Entrar
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
