// lib/relatorio/documento_relatorio_widget.dart
// Exibe na tela os mesmos blocos que serão renderizados no .docx (revisão antes da emissão).
import 'package:flutter/material.dart';
import 'relatorio_documento.dart';

class DocumentoRelatorioWidget extends StatelessWidget {
  final DocumentoRelatorio documento;

  const DocumentoRelatorioWidget({super.key, required this.documento});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(documento.titulo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),
          ...documento.blocos.map(_bloco),
        ],
      ),
    );
  }

  Widget _bloco(BlocoRelatorio bloco) {
    switch (bloco) {
      case BlocoTitulo(:final texto, :final nivel):
        return Padding(
          padding: EdgeInsets.only(top: nivel == 1 ? 16 : 10, bottom: 6),
          child: Text(texto,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: nivel == 1 ? 15 : 13.5, color: Colors.blue[800])),
        );
      case BlocoParagrafo(:final texto, :final rotulo):
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(TextSpan(children: [
            if (rotulo != null) TextSpan(text: '$rotulo ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: texto),
          ])),
        );
      case BlocoLista(:final itens, :final numerada):
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < itens.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text('${numerada ? '${i + 1}.' : '•'} ${itens[i]}'),
                ),
            ],
          ),
        );
      case BlocoTabela(:final cabecalho, :final linhas):
        final colunas = [cabecalho.length, ...linhas.map((l) => l.length)].reduce((a, b) => a > b ? a : b);
        List<String> completar(List<String> l) => [...l, ...List.filled(colunas - l.length, '')];
        if (colunas == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade400),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              if (cabecalho.isNotEmpty)
                TableRow(
                  decoration: BoxDecoration(color: Colors.blue.shade50),
                  children: completar(cabecalho).map((c) => _celula(c, cabecalho: true)).toList(),
                ),
              ...linhas.map((l) => TableRow(children: completar(l).map(_celula).toList())),
            ],
          ),
        );
      case BlocoImagem(:final url, :final legenda):
        final remota = url.startsWith('https://');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              if (remota)
                Image.network(url, height: 180, errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48))
              else
                const Text('(imagem pendente de envio)', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              Text(legenda, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        );
    }
  }

  Widget _celula(String texto, {bool cabecalho = false}) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(texto, style: TextStyle(fontSize: 12, fontWeight: cabecalho ? FontWeight.bold : FontWeight.normal)),
      );
}
