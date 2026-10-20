// lib/integridade_pesagem_form.dart
import 'package:flutter/material.dart';

const Map<String, String> rotulosParcialIntegridade = {
  'assentamento': 'Assentamento do filtro',
  'estrutura': 'Estrutura do filtro',
  'meioFiltrante': 'Meio filtrante',
};

const List<String> acoesCorretivasIntegridade = [
  'Reaperto dos parafusos de fixação',
  'Reparo do filtro',
  'Troca da gaxeta',
  'Troca do filtro',
];

class IntegridadePesagemForm extends StatefulWidget {
  final Map<String, dynamic> valor;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const IntegridadePesagemForm({super.key, required this.valor, required this.onChanged});

  @override
  State<IntegridadePesagemForm> createState() => _IntegridadePesagemFormState();
}

class _IntegridadePesagemFormState extends State<IntegridadePesagemForm> {
  late final TextEditingController _reparoX;
  late final TextEditingController _reparoY;
  late final TextEditingController _reparoArea;

  @override
  void initState() {
    super.initState();
    _reparoX = TextEditingController(text: widget.valor['reparoX']?.toString() ?? '');
    _reparoY = TextEditingController(text: widget.valor['reparoY']?.toString() ?? '');
    _reparoArea = TextEditingController(text: widget.valor['reparoAreaCm2']?.toString() ?? '');
  }

  @override
  void dispose() {
    _reparoX.dispose();
    _reparoY.dispose();
    _reparoArea.dispose();
    super.dispose();
  }

  void _alterar(Map<String, dynamic> alteracao) => widget.onChanged({...widget.valor, ...alteracao});

  @override
  Widget build(BuildContext context) {
    final parcial = Map<String, dynamic>.from(widget.valor['parcial'] as Map? ?? const {});
    final acoes = List<String>.from(widget.valor['acoesCorretivas'] as List? ?? const []);
    const numerico = TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Resultado parcial', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final entrada in rotulosParcialIntegridade.entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<bool?>(
              initialValue: parcial[entrada.key] as bool?,
              decoration: InputDecoration(labelText: entrada.value),
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('Selecione')),
                DropdownMenuItem<bool?>(value: true, child: Text('Conforme')),
                DropdownMenuItem<bool?>(value: false, child: Text('Não conforme')),
              ],
              onChanged: (valor) => _alterar({'parcial': {...parcial, entrada.key: valor}}),
            ),
          ),
        const SizedBox(height: 20),
        const Text('Ações corretivas (se não conforme)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final acao in acoesCorretivasIntegridade)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(acao),
            value: acoes.contains(acao),
            onChanged: (marcado) => _alterar({
              'acoesCorretivas': [...acoes.where((item) => item != acao), if (marcado == true) acao],
            }),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _reparoX,
          keyboardType: numerico,
          decoration: const InputDecoration(labelText: 'Localização do reparo: X (mm)'),
          onChanged: (valor) => _alterar({'reparoX': valor}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reparoY,
          keyboardType: numerico,
          decoration: const InputDecoration(labelText: 'Localização do reparo: Y (mm)'),
          onChanged: (valor) => _alterar({'reparoY': valor}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reparoArea,
          keyboardType: numerico,
          decoration: const InputDecoration(labelText: 'Área total do reparo (cm²)'),
          onChanged: (valor) => _alterar({'reparoAreaCm2': valor}),
        ),
        if (acoes.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<bool?>(
            initialValue: widget.valor['novoEnsaioConforme'] as bool?,
            decoration: const InputDecoration(labelText: 'Novo ensaio após ações corretivas'),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Selecione')),
              DropdownMenuItem<bool?>(value: true, child: Text('Conforme')),
              DropdownMenuItem<bool?>(value: false, child: Text('Não conforme')),
            ],
            onChanged: (valor) => _alterar({'novoEnsaioConforme': valor}),
          ),
        ],
      ],
    );
  }
}
