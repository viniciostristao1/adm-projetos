import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Trava contra o dessync (ex.: topo em V0.1.159 com pubspec em 0.1.162):
/// `lib/versao.dart` é GERADO a partir do `version:` do pubspec.yaml
/// (`dart tool/gerar_versao.dart`; o CI gera a cada build). Este teste garante
/// que o commit está consistente — rode o gerador após bumpar o pubspec.
void main() {
  test('versao.dart == version do pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final mp = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+', multiLine: true)
        .firstMatch(pub);
    expect(mp, isNotNull,
        reason: "'version: X.Y.Z+N' ausente no pubspec.yaml");
    final dart = File('lib/versao.dart').readAsStringSync();
    final md = RegExp(r"appVersao = 'V([0-9]+\.[0-9]+\.[0-9]+)'")
        .firstMatch(dart);
    expect(md, isNotNull,
        reason: "const appVersao = 'VX.Y.Z' ausente em lib/versao.dart");
    expect(md!.group(1), equals(mp!.group(1)),
        reason:
            "rode 'dart tool/gerar_versao.dart' após bumpar o pubspec.yaml");
  });

  test('versao.dart avisa que é gerado', () {
    expect(
        File('lib/versao.dart').readAsStringSync(), contains('GERADO'));
  });

  // GUARDRAIL anti-dessync entre o pubspec e o CHANGELOG do AGENTS.md
  // (incidente V0.1.163: commits/changelog em V0.1.163 mas pubspec parado em
  // 0.1.162 → APK saiu nomeado v0.1.162 e o app exibia V0.1.162). O teste
  // acima só comparava versao.dart↔pubspec e passava. Agora: a entrada MAIS
  // NOVA do changelog ("- **V0.1.N") TEM de bater com o pubspec. Assim, toda
  // versão nova obriga bumpar o pubspec E criar a entrada — nenhuma IA se perde.
  test('pubspec == entrada mais nova do changelog do AGENTS.md', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final mp = RegExp(r'^version:\s*[0-9]+\.[0-9]+\.([0-9]+)\+', multiLine: true)
        .firstMatch(pub);
    expect(mp, isNotNull, reason: "'version:' ausente no pubspec.yaml");
    final pubN = int.parse(mp!.group(1)!);

    final agents = File('AGENTS.md').readAsStringSync();
    final ns = RegExp(r'^- \*\*V0\.1\.([0-9]+)', multiLine: true)
        .allMatches(agents)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(ns, isNotEmpty,
        reason: 'nenhuma entrada "- **V0.1.N" no changelog do AGENTS.md');
    final maxN = ns.reduce((a, b) => a > b ? a : b);

    expect(pubN, equals(maxN),
        reason: 'DESSYNC: pubspec está em 0.1.$pubN, mas a entrada mais nova '
            'do changelog do AGENTS.md é V0.1.$maxN. Ao publicar uma versão: '
            'bump o pubspec.yaml, regenere o versao.dart E adicione a entrada '
            '"- **V0.1.$pubN — ..." no AGENTS.md (§12 do fluxo de release).');
  });
}
