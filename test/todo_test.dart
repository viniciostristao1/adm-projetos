import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adm_projetos/editor.dart';
import 'package:adm_projetos/models.dart';

const TextStyle _estiloTexto = TextStyle(fontSize: 14.5, height: 1.35);

/// Réplica EXATA da lógica de `_toqueTexto` do projeto_screen.dart
String toque(TextEditingController ctrl, Offset toqueGlobal,
    GlobalKey campoKey, ScrollController scroll) {
  final texto = ctrl.text;
  if (!texto.contains('☐') && !texto.contains('☑')) return texto;
  final ctx = campoKey.currentContext;
  if (ctx == null) return texto;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return texto;
  final local = box.globalToLocal(toqueGlobal);
  final dx = local.dx - 14;
  if (dx < 0 || dx > 40) return texto;
  final dy = local.dy + (scroll.hasClients ? scroll.offset : 0.0) - 2;
  if (dy < 0) return texto;
  final painter = TextPainter(
    text: TextSpan(text: texto, style: _estiloTexto),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(ctx),
  )..layout(maxWidth: box.size.width - 28);
  final pos = painter.getPositionForOffset(
      Offset(dx.clamp(0.0, painter.width), dy));
  final offset = pos.offset.clamp(0, texto.length);
  var inicio = texto.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
  inicio = inicio < 0 ? 0 : inicio + 1;
  var fim = texto.indexOf('\n', offset);
  if (fim < 0) fim = texto.length;
  final linha = texto.substring(inicio, fim);
  final m = RegExp(r'^\s*(☐|☑)').firstMatch(linha);
  if (m == null) return texto;
  final idx = inicio + m.start + m.group(0)!.indexOf(m.group(1)!);
  final novoChar = texto[idx] == '☐' ? '☑' : '☐';
  var pos2 = idx + 1;
  if (pos2 < texto.length && texto.codeUnitAt(pos2) == 0xFE0E) pos2++;
  final novo = '${texto.substring(0, idx)}$novoChar'
      '\uFE0E'
      '${texto.substring(pos2)}';
  ctrl.value = TextEditingValue(
    text: novo,
    selection: TextSelection.collapsed(offset: offset.clamp(0, novo.length)),
  );
  return novo;
}

void main() {
  group('Enter depois de linha com ☐ ou ☑', () {
    test('continua com ☐ depois de linha ☐', () {
      final f = LinhasNumeradas();
      final res = f.formatEditUpdate(
        TextEditingValue(text: '☐\uFE0E item'),
        TextEditingValue(text: '☐\uFE0E item\n'),
      );
      expect(res.text, '☐\uFE0E item\n☐\uFE0E ');
    });

    test('continua com ☐ depois de linha JÁ MARCADA ☑ (bug: hoje não cria)',
        () {
      final f = LinhasNumeradas();
      final res = f.formatEditUpdate(
        TextEditingValue(text: '☑\uFE0E item'),
        TextEditingValue(text: '☑\uFE0E item\n'),
      );
      expect(res.text, '☑\uFE0E item\n☐\uFE0E ');
    });

    test('dado antigo sem VS15, Enter cria ☐ com VS15', () {
      final f = LinhasNumeradas();
      final res = f.formatEditUpdate(
        TextEditingValue(text: '☑ item'),
        TextEditingValue(text: '☑ item\n'),
      );
      expect(res.text, '☑ item\n☐\uFE0E ');
    });
  });

  group('dados antigos sem VS15', () {
    test('Nota.fromJson normaliza ☑/☐ para texto (adiciona \\uFE0E)', () {
      final n = Nota.fromJson({'id': '1', 'texto': '☑ comprar\n☐ ligar'});
      expect(n.texto, '☑\uFE0E comprar\n☐\uFE0E ligar');
    });
  });

  testWidgets('toque em dado antigo (☐ sem VS15) produz ☑ com VS15',
      (tester) async {
    final ctrl = TextEditingController();
    final campoKey = GlobalKey();
    final scroll = ScrollController();

    ctrl.text = '☐ comprar pão\n☐ ligar para o João';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: TextField(
              key: campoKey,
              controller: ctrl,
              scrollController: scroll,
              minLines: 1,
              maxLines: 24,
              style: _estiloTexto,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(14, 2, 14, 14),
              ),
            ),
          ),
        ),
      ),
    ));

    final box = campoKey.currentContext!.findRenderObject() as RenderBox;
    final painter = TextPainter(
      text: TextSpan(text: ctrl.text, style: _estiloTexto),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(campoKey.currentContext!),
    )..layout(maxWidth: box.size.width - 28);
    final lines = painter.computeLineMetrics();

    Offset tap(double y) => Offset(
        box.localToGlobal(Offset(20, y)).dx,
        box.localToGlobal(Offset(0, y)).dy);

    final res1 = toque(ctrl, tap(lines[0].height / 2), campoKey, scroll);
    debugPrint('após toque linha1 (dado antigo): "$res1"');
    expect(res1, contains('☑\uFE0E comprar pão'));
    expect(res1, isNot(contains('☑ ')));

    ctrl.text = '☐ comprar pão\n☐ ligar para o João';
    final res2 = toque(
        ctrl, tap(lines[0].height + lines[1].height / 2), campoKey, scroll);
    debugPrint('após toque linha2 (dado antigo): "$res2"');
    expect(res2, contains('☑\uFE0E ligar para o João'));
  });
}
