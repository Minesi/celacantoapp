// lib/perfil_page.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'auth_service.dart';
import 'cloud_functions_client.dart';
import 'offline_authorization_service.dart';

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
  final _offlineAuthorizationService = OfflineAuthorizationService.instance;

  final _senhaAtualController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmaNovaSenhaController = TextEditingController(); // Adicionado para validação

  // Controles de visibilidade das senhas (olhinho)
  bool _ocultarSenhaAtual = true;
  bool _ocultarNovaSenha = true;
  bool _ocultarConfirmaNovaSenha = true;

  Map<String, dynamic>? _dadosUsuario;
  bool _carregandoDados = true;
  bool _autenticadorAtivo = false;
  bool _autorizacaoOfflineConfigurada = false;

  bool get _podeLiberar =>
      widget.perfilLogado == PerfilUsuario.supervisor || widget.perfilLogado == PerfilUsuario.admin;

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
      _autenticadorAtivo = dados?['totpAtivo'] == true;
      _carregandoDados = false;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final chave = await _offlineAuthorizationService.publicKeyLocal(uid);
      if (!mounted) return;
      setState(() => _autorizacaoOfflineConfigurada = chave != null);
    }
  }

  Future<void> _configurarAutenticador() async {
    final Map<String, dynamic> config;
    try {
      config = await chamarCallable('configurarAutenticador', {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível iniciar a configuração: $e'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!mounted) return;

    final uri = config['uri']?.toString() ?? '';
    final segredo = config['segredo']?.toString() ?? '';
    final codigoController = TextEditingController();
    String? erro;
    bool confirmando = false;

    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Configurar autenticador'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('1. No Google Authenticator, toque em "+" e leia o QR code abaixo.'),
                const SizedBox(height: 12),
                SizedBox(width: 200, height: 200, child: QrImageView(data: uri, backgroundColor: Colors.white)),
                const SizedBox(height: 8),
                const Text('Ou digite a chave manualmente:', style: TextStyle(fontSize: 12)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: SelectableText(segredo, style: const TextStyle(fontFamily: 'monospace'))),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: segredo)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('2. Digite o código de 6 dígitos exibido no app para confirmar.'),
                TextField(
                  controller: codigoController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(counterText: '', errorText: erro),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: confirmando
                  ? null
                  : () async {
                      setDialogState(() {
                        confirmando = true;
                        erro = null;
                      });
                      try {
                        await chamarCallable('confirmarAutenticador', {'codigo': codigoController.text.trim()});
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on FirebaseFunctionsException catch (e) {
                        setDialogState(() {
                          confirmando = false;
                          erro = e.code == 'invalid-argument' ? 'Código incorreto' : (e.message ?? e.code);
                        });
                      } catch (e) {
                        setDialogState(() {
                          confirmando = false;
                          erro = 'Falha de conexão';
                        });
                      }
                    },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (confirmado == true && mounted) {
      setState(() => _autenticadorAtivo = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autenticador configurado!'), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildSecaoAutenticador() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.verified_user_outlined, color: _autenticadorAtivo ? Colors.green : Colors.grey),
        title: const Text('Autenticador de liberação'),
        subtitle: Text(_autenticadorAtivo
            ? 'Ativo. Envie ao técnico o código do Google Authenticator para liberar ações.'
            : 'Não configurado. Configure para liberar técnicos por código.'),
        trailing: TextButton(
          onPressed: _configurarAutenticador,
          child: Text(_autenticadorAtivo ? 'Reconfigurar' : 'Configurar'),
        ),
      ),
    );
  }

  Future<String?> _solicitarPinOffline({required bool confirmar}) async {
    final pinController = TextEditingController();
    final confirmacaoController = TextEditingController();
    String? erro;
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(confirmar ? 'Configurar autorização offline' : 'Autorizar solicitação offline'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(labelText: 'PIN do supervisor'),
              ),
              if (confirmar) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmacaoController,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(labelText: 'Confirmar PIN'),
                ),
              ],
              if (erro != null) ...[
                const SizedBox(height: 12),
                Text(erro!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final pin = pinController.text;
                if (pin.length < 6 || pin.length > 32) {
                  setDialogState(() => erro = 'Use um PIN entre 6 e 32 caracteres.');
                  return;
                }
                if (confirmar && pin != confirmacaoController.text) {
                  setDialogState(() => erro = 'Os PINs não coincidem.');
                  return;
                }
                Navigator.of(dialogContext).pop(pin);
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    pinController.dispose();
    confirmacaoController.dispose();
    return resultado;
  }

  Future<void> _configurarAutorizacaoOffline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pin = await _solicitarPinOffline(confirmar: true);
    if (pin == null || !mounted) return;

    try {
      final publicKey = await _offlineAuthorizationService.criarChaveSupervisor(
        supervisorUid: uid,
        pin: pin,
      );
      await chamarCallable('registrarChaveAutorizacaoOffline', {'publicKey': publicKey});
      if (!mounted) return;
      setState(() => _autorizacaoOfflineConfigurada = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autorização offline configurada.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível configurar a autorização offline: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _assinarSolicitacaoOffline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pin = await _solicitarPinOffline(confirmar: false);
    if (pin == null || !mounted) return;

    final solicitacaoController = TextEditingController();
    String? resposta;
    String? erro;
    bool processando = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Assinar solicitação offline'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Cole abaixo a solicitação recebida do técnico.'),
                const SizedBox(height: 12),
                TextField(
                  controller: solicitacaoController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Solicitação', border: OutlineInputBorder()),
                ),
                if (resposta != null) ...[
                  const SizedBox(height: 16),
                  const Text('Envie este token assinado ao técnico:'),
                  const SizedBox(height: 8),
                  SelectableText(resposta!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  IconButton(
                    tooltip: 'Copiar autorização',
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(ClipboardData(text: resposta!)),
                  ),
                ],
                if (erro != null) ...[
                  const SizedBox(height: 12),
                  Text(erro!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: processando ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: processando
                  ? null
                  : () async {
                      setDialogState(() {
                        processando = true;
                        erro = null;
                      });
                      try {
                        final token = await _offlineAuthorizationService.assinarSolicitacao(
                          supervisorUid: uid,
                          supervisorNome: _dadosUsuario?['nome']?.toString() ?? '',
                          supervisorEmail: widget.emailLogado,
                          pin: pin,
                          requestToken: solicitacaoController.text.trim(),
                        );
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          resposta = token;
                          processando = false;
                        });
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          erro = 'Solicitação inválida ou expirada.';
                          processando = false;
                        });
                      }
                    },
              child: Text(processando ? 'Assinando...' : 'Assinar'),
            ),
          ],
        ),
      ),
    );
    solicitacaoController.dispose();
  }

  Widget _buildSecaoAutorizacaoOffline() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.key_outlined, color: _autorizacaoOfflineConfigurada ? Colors.green : Colors.grey),
              title: const Text('Autorização offline assinada'),
              subtitle: Text(_autorizacaoOfflineConfigurada
                  ? 'Chave configurada neste dispositivo.'
                  : 'Configure uma chave para autorizar solicitações sem internet.'),
              trailing: TextButton(
                onPressed: _configurarAutorizacaoOffline,
                child: Text(_autorizacaoOfflineConfigurada ? 'Reconfigurar' : 'Configurar'),
              ),
            ),
            if (_autorizacaoOfflineConfigurada)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _assinarSolicitacaoOffline,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Assinar solicitação'),
                ),
              ),
          ],
        ),
      ),
    );
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

  Future<void> _solicitarExclusaoConta() async {
    final senhaController = TextEditingController();
    final confirmacaoController = TextEditingController();
    String? erro;
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Excluir minha conta?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Seu acesso e seu perfil serão excluídos. Projetos e relatórios técnicos já emitidos serão mantidos para o histórico da empresa.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: senhaController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha atual'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmacaoController,
                  decoration: const InputDecoration(labelText: 'Digite EXCLUIR para confirmar'),
                ),
                if (erro != null) ...[
                  const SizedBox(height: 12),
                  Text(erro!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (senhaController.text.isEmpty) {
                  setDialogState(() => erro = 'Informe sua senha atual.');
                  return;
                }
                if (confirmacaoController.text.trim().toUpperCase() != 'EXCLUIR') {
                  setDialogState(() => erro = 'Digite EXCLUIR para confirmar.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Excluir conta'),
            ),
          ],
        ),
      ),
    );
    final senha = senhaController.text;
    senhaController.dispose();
    confirmacaoController.dispose();
    if (confirmado != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final sucesso = await _authService.excluirMinhaConta(senhaAtual: senha);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (sucesso) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir a conta. Verifique a senha e se existe outro administrador.'),
          backgroundColor: Colors.red,
        ),
      );
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

                      if (_podeLiberar) ...[
                        _buildSecaoAutenticador(),
                        const SizedBox(height: 16),
                        _buildSecaoAutorizacaoOffline(),
                        const SizedBox(height: 32),
                      ],

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
                      OutlinedButton.icon(
                        onPressed: _solicitarExclusaoConta,
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Excluir minha conta'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}