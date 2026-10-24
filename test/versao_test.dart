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
}
