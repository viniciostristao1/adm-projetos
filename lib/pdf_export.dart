import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

/// Remove caracteres fora do BMP (emojis) e troca os quadradinhos de to-do
/// por marcadores de texto — as fontes padrão do PDF não os suportam.
String _textoPdf(String s) {
  var t = s.replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '');
  t = t.replaceAll('\u2610\uFE0E', '[ ]').replaceAll('\u2611\uFE0E', '[x]');
  t = t.replaceAll('\u2610', '[ ]').replaceAll('\u2611', '[x]');
  return t;
}

/// Gera um PDF com o projeto inteiro (Tarefas + Futuro) e abre a tela de
/// compartilhamento do Android (salvar, enviar, etc.).
Future<void> exportarPdfProjeto(BuildContext context, Projeto p) async {
  final doc = pw.Document();

  pw.Widget secao(String titulo, List<Nota> notas) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titulo,
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final n in notas) ...[
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8, top: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300)),
              ),
              child: pw.Text(
                (n.concluida ? '[x] ' : '') + _textoPdf(n.texto),
                style: pw.TextStyle(
                  fontSize: 12,
                  color: n.concluida ? PdfColors.grey600 : PdfColors.black,
                ),
              ),
            ),
          ],
        ],
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Text(p.nome,
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Gerado pelo ADM-projetos',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 16),
        if (p.tarefas.isNotEmpty) secao('Tarefas', p.tarefas),
        if (p.tarefas.isNotEmpty && p.futuro.isNotEmpty) pw.SizedBox(height: 16),
        if (p.futuro.isNotEmpty) secao('Futuro', p.futuro),
      ],
    ),
  );

  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: '${p.nome}.pdf');
}
