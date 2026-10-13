// lib/usuario_model.dart
import 'auth_service.dart'; // Importa o seu enum PerfilUsuario existente

class UsuarioModel {
  final String uid;             // ID único gerado pelo Firebase Auth
  final String nome;            // Mantendo a variável 'nome' do seu SQLite
  final String cpf;             // Mantendo a variável 'cpf' do seu SQLite
  final String email;           // Mantendo a variável 'email' do seu SQLite
  final PerfilUsuario perfil;   // Mantendo seu enum (admin, tecnico, supervisor, redator)
  final String dominioEmpresa;  // O domínio isolador extraído do e-mail (@empresa.com)

  UsuarioModel({
    required this.uid,
    required this.nome,
    required this.cpf,
    required this.email,
    required this.perfil,
    required this.dominioEmpresa,
  });

  // Reconstrói o Objeto a partir de um documento do Firestore
  factory UsuarioModel.fromFirestore(Map<String, dynamic> data, String id) {
    // Tratamento para converter a String de volta para o seu Enum PerfilUsuario
    PerfilUsuario perfilConvertido = PerfilUsuario.tecnico;
    if (data['perfil'] != null) {
      perfilConvertido = PerfilUsuario.values.firstWhere(
        (p) => p.name == data['perfil'],
        orElse: () => PerfilUsuario.tecnico,
      );
    }

    return UsuarioModel(
      uid: id,
      nome: data['nome'] ?? '',
      cpf: data['cpf'] ?? '',
      email: data['email'] ?? '',
      perfil: perfilConvertido,
      dominioEmpresa: data['dominio_empresa'] ?? '',
    );
  }
}