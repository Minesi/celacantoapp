// lib/filtro_projetos_bar.dart
// Barra de busca dos pré-relatórios por empresa (CNPJ), tipo de teste, área e data.
import 'package:flutter/material.dart';

class FiltroProjetos {
  final String? cnpj;
  final String? tipoProjeto;
  final String area;
  final DateTime? data;

  const FiltroProjetos({this.cnpj, this.tipoProjeto, this.area = '', this.data});

  bool get vazio => cnpj == null && tipoProjeto == null && area.trim().isEmpty && data == null;

  List<Map<String, dynamic>> aplicar(List<Map<String, dynamic>> projetos) {
    final areaBusca = area.trim().toLowerCase();
    return projetos.where((p) {
      if (cnpj != null && p['cnpjEmpresa']?.toString() != cnpj) return false;
      if (tipoProjeto != null && p['tipoProjeto']?.toString() != tipoProjeto) return false;
      if (areaBusca.isNotEmpty && !(p['area']?.toString() ?? '').toLowerCase().contains(areaBusca)) return false;
      if (data != null) {
        final criado = DateTime.tryParse(p['dataCriacao']?.toString() ?? '');
        if (criado == null || !DateUtils.isSameDay(criado, data)) return false;
      }
      return true;
    }).toList();
  }
}

class FiltroProjetosBar extends StatefulWidget {
  final List<Map<String, dynamic>> projetos;
  final Map<String, String> nomeEmpresaPorCnpj;
  final FiltroProjetos filtro;
  final ValueChanged<FiltroProjetos> onChanged;

  const FiltroProjetosBar({
    super.key,
    required this.projetos,
    required this.nomeEmpresaPorCnpj,
    required this.filtro,
    required this.onChanged,
  });

  @override
  State<FiltroProjetosBar> createState() => _FiltroProjetosBarState();
}

class _FiltroProjetosBarState extends State<FiltroProjetosBar> {
  late final TextEditingController _areaController = TextEditingController(text: widget.filtro.area);

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  void _emitir({String? cnpj, String? tipo, DateTime? data, bool limparCnpj = false, bool limparTipo = false, bool limparData = false}) {
    final f = widget.filtro;
    widget.onChanged(FiltroProjetos(
      cnpj: limparCnpj ? null : (cnpj ?? f.cnpj),
      tipoProjeto: limparTipo ? null : (tipo ?? f.tipoProjeto),
      area: _areaController.text,
      data: limparData ? null : (data ?? f.data),
    ));
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: widget.filtro.data ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (escolhida != null) _emitir(data: escolhida);
  }

  @override
  Widget build(BuildContext context) {
    final cnpjs = widget.projetos.map((p) => p['cnpjEmpresa']?.toString() ?? '').where((c) => c.isNotEmpty).toSet().toList();
    final tipos = widget.projetos.map((p) => p['tipoProjeto']?.toString() ?? '').where((t) => t.isNotEmpty).toSet().toList()..sort();
    final data = widget.filtro.data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('cnpj-${widget.filtro.cnpj}'),
              initialValue: widget.filtro.cnpj,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Empresa', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                ...cnpjs.map((c) => DropdownMenuItem<String?>(value: c, child: Text(widget.nomeEmpresaPorCnpj[c] ?? c, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (c) => c == null ? _emitir(limparCnpj: true) : _emitir(cnpj: c),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('tipo-${widget.filtro.tipoProjeto}'),
              initialValue: widget.filtro.tipoProjeto,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de teste', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                ...tipos.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
              ],
              onChanged: (t) => t == null ? _emitir(limparTipo: true) : _emitir(tipo: t),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'Área', isDense: true, prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _emitir(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _escolherData,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(data == null
                ? 'Data'
                : '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}'),
          ),
          if (!widget.filtro.vazio)
            TextButton(
              onPressed: () {
                _areaController.clear();
                widget.onChanged(const FiltroProjetos());
              },
              child: const Text('Limpar filtros'),
            ),
        ],
      ),
    );
  }
}
