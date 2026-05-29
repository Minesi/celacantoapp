// lib/home_page.dart
import 'package:celacantoapp/editar_banco_dados_page.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart'; // Importante para reconhecer o PerfilUsuario
import 'cadastro_page.dart';
import 'novo_projeto_page.dart';
import 'perfil_page.dart';
import 'ocr_scanner_page.dart'; 
import 'qr_code_scanner_page.dart';

class HomePage extends StatelessWidget {
  final PerfilUsuario perfil;
  final String nomeUsuario;
  final String emailUsuario; // Ajustado de dynamic para String para evitar conflitos de tipo

  const HomePage({
    super.key,
    required this.perfil,
    required this.nomeUsuario,
    required this.emailUsuario,
  });

  // Regra de negócio: Apenas Supervisor e Admin podem acessar
  bool get _temAcessoAvancado {
    return perfil == PerfilUsuario.supervisor || perfil == PerfilUsuario.admin;
  }

  // Regra de negócio exclusiva para os novos botões: Apenas Admin pode acessar
  bool get _ehAdmin {
    return perfil == PerfilUsuario.admin;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50]!,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- PARTE SUPERIOR: Logo (Esquerda) e Usuário (Direita) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo.png', height: 40),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Olá, $nomeUsuario',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Acesso: ${perfil.name.toUpperCase()}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              
              // --- CORPO CENTRALIZADO: Menu de Botões ---
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    // Usando SingleChildScrollView para evitar estouro de tela (overflow) com os novos botões
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Botão: Novo Projeto (Livre)
                          _buildMenuButton(
                            label: 'Novo Projeto',
                            icon: Icons.add_box_outlined,
                            isEnable: true,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const NovoProjetoPage()
                                )
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Botão: Editar Projeto (Restrito)
                          _buildMenuButton(
                            label: 'Editar Projeto',
                            icon: Icons.edit_note_outlined,
                            isEnable: _temAcessoAvancado,
                            onPressed: () {
                              _mostrarAlerta(context, 'Abrindo: Editar Projeto');
                            },
                          ),
                          const SizedBox(height: 12),

                          // Botão: Perfil (Livre)
                          _buildMenuButton(
                            label: 'Perfil',
                            icon: Icons.account_circle_outlined,
                            isEnable: true,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PerfilPage(
                                    perfilLogado: perfil,
                                    emailLogado: emailUsuario,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Botão: Cadastrar novo usuário (Restrito)
                          _buildMenuButton(
                            label: 'Cadastrar Novo Usuário',
                            icon: Icons.person_add_alt_1_outlined,
                            isEnable: _temAcessoAvancado,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CadastroPage(
                                    perfilLogado: perfil,
                                    emailLogado: emailUsuario,
                                    nomeLogado: nomeUsuario,
                                  ),
                                ),
                              );
                            },
                          ),

                          // ==========================================================
                          // NOVOS BOTÕES: Renderizados e acessados apenas se for ADMIN
                          // ==========================================================
                          if (_ehAdmin) ...[
                            const SizedBox(height: 12),
                            _buildMenuButton(
                              label: 'Editar Banco de dados',
                              icon: Icons.storage_outlined,
                              isEnable: true, // Sempre ativo para quem consegue ver (Admin)
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditarBancoDadosPage(
                                      perfilLogado: perfil,
                                      nomeLogado: nomeUsuario,
                                    ),
                                  ),
                                );
                                _mostrarAlerta(context, 'Abrindo Painel do Banco de Dados');
                              },
                            ),
                            const SizedBox(height: 12),
                            
                            // Botão: Teste QR Code
                            _buildMenuButton(
                              label: 'Teste QR Code',
                              icon: Icons.qr_code_scanner_outlined,
                              isEnable: true,
                              onPressed: () => _abrirLeitorQrCode(context),
                            ),
                            const SizedBox(height: 12),

                            // Botão: Teste OCR ajustado para chamar o método assíncrono isolado
                            _buildMenuButton(
                              label: 'Teste OCR',
                              icon: Icons.document_scanner_outlined,
                              isEnable: true,
                              onPressed: () => _abrirLeitorOcr(context),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // --- PARTE INFERIOR: Versão do App ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'v0.1',
                    style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.exit_to_app, size: 16, color: Colors.red),
                    label: const Text('Sair', style: TextStyle(color: Colors.red)),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Componente de botão reutilizável que aplica o efeito esmaecido
  Widget _buildMenuButton({
    required String label,
    required IconData icon,
    required bool isEnable,
    required VoidCallback? onPressed,
  }) {
    return Opacity(
      // Se estiver desativado, aplica opacidade de 35% (efeito esmaecido)
      opacity: isEnable ? 1.0 : 0.35, 
      child: ElevatedButton.icon(
        onPressed: isEnable ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          alignment: Alignment.centerLeft, // Alinha o texto à esquerda dentro do botão
          elevation: isEnable ? 2 : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _mostrarAlerta(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), duration: const Duration(seconds: 1)),
    );
  }

  // --- FUNÇÃO ASSÍNCRONA DO QR CODE ---
  Future<void> _abrirLeitorQrCode(BuildContext context) async {
    // Abre a tela da câmera e aguarda o retorno da String do QR Code
    final String? resultadoQrCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrCodeScannerPage()),
    );

    // Se o usuário cancelou e voltou sem ler nada, encerra a função
    if (resultadoQrCode == null) return;
    
    // Verificação de segurança para o build context em métodos assíncronos
    if (!context.mounted) return;

    // Apresenta a mensagem com o texto que foi lido
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('QR Code lido com sucesso: $resultadoQrCode'),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 5), // Tempo maior para leitura de texto longo
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  // --- FUNÇÃO ASSÍNCRONA DO OCR ---
  Future<void> _abrirLeitorOcr(BuildContext context) async {
    // Abre a tela da câmera do OCR e aguarda a String de texto retornar
    final String? textoDetectado = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const OcrScannerPage()),
    );

    // Se cancelou ou voltou sem ler nada, encerra a função
    if (textoDetectado == null) return;
    
    // Verificação de segurança para contextos assíncronos
    if (!context.mounted) return;

    // Apresenta o resultado que o OCR extraiu do display em um diálogo limpo
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.document_scanner, color: Colors.blue),
              SizedBox(width: 8),
              Text('Texto Lido via OCR'),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              textoDetectado,
              style: const TextStyle(fontSize: 16, fontFamily: 'Courier'), // Fonte estilo display
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }
}