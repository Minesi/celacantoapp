// lib/auth_service.dart
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

enum PerfilUsuario { operador, supervisor, admin }

// Classe auxiliar para transportar os dados do banco para as telas
class UsuarioLogado {
  final String nome;
  final PerfilUsuario perfil;
  UsuarioLogado({required this.nome, required this.perfil});
}

class AuthService {
  // LOCAL: lib/auth_service.dart (Dentro da classe AuthService)

Future<bool> verificarSeEmailExiste(String email) async {
  final db = await _dbHelper.database;
  final List<Map<String, dynamic>> resultado = await db.query(
    'usuarios',
    where: 'email = ?',
    whereArgs: [email.trim().toLowerCase()],
  );
  
  return resultado.isNotEmpty;
}
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Agora retorna o objeto UsuarioLogado com o Nome Real vindo do SQL
  Future<UsuarioLogado?> loginLocal(String usuario, String senha) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> resultado = await db.query(
      'usuarios',
      where: 'email = ? AND senha = ?',
      whereArgs: [usuario, senha],
    );

    if (resultado.isNotEmpty) {
      String nomeBanco = resultado.first['nome'] as String;
      String perfilStr = resultado.first['perfil'] as String;
      
      return UsuarioLogado(
        nome: nomeBanco,
        perfil: PerfilUsuario.values.firstWhere((e) => e.name == perfilStr),
      );
    }
    return null;
  }

  // Salvando Nome Completo e CPF recebidos da tela de cadastro
  Future<bool> cadastrarUsuarioNoBanco({
    required String nome,
    required String cpf,
    required String email, 
    required String senha, 
    required PerfilUsuario perfil,
  }) async {
    final db = await _dbHelper.database;

    try {
      await db.insert(
        'usuarios',
        {
          'nome': nome,
          'cpf': cpf,
          'email': email,
          'senha': senha,
          'perfil': perfil.name,
        },
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
      return true;
    } catch (e) {
      return false; 
    }
  }
// 1. Busca os dados completos do usuário pelo e-mail (ou você pode adaptar para nome/id se preferir)
Future<Map<String, dynamic>?> buscarDadosUsuario(String email) async {
  final db = await _dbHelper.database;
  final List<Map<String, dynamic>> resultado = await db.query(
    'usuarios',
    where: 'email = ?',
    whereArgs: [email],
  );
  
  if (resultado.isNotEmpty) {
    return resultado.first;
  }
  return null;
}

// 2. Atualiza a senha no banco de dados se a senha atual estiver correta
Future<bool> atualizarSenha({
  required String emailUsuario,
  required String senhaAtual,
  required String novaSenha,
}) async {
  final db = await _dbHelper.database;

  // Primeiro, valida se a senha atual está correta no banco
  final List<Map<String, dynamic>> checagem = await db.query(
    'usuarios',
    where: 'email = ? AND senha = ?',
    whereArgs: [emailUsuario, senhaAtual],
  );

  if (checagem.isEmpty) {
    return false; // Senha atual incorreta
  }

  // Se estiver correta, faz o UPDATE para a nova senha
  await db.update(
    'usuarios',
    {'senha': novaSenha},
    where: 'email = ?',
    whereArgs: [emailUsuario],
  );
  
  return true;
}
}