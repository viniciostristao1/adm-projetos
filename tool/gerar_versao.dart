// Gera lib/versao.dart a partir do `version:` do pubspec.yaml (fonte única).
//
// Uso local:  dart tool/gerar_versao.dart   (na raiz do projeto)
// O CI (build-apk.yml) roda isso a cada build, antes de compilar — o APK
// nunca mais sai com a versão do topo dessincronizada (incidente V0.1.159
// exibida com pubspec em 0.1.162).
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+', multiLine: true)
      .firstMatch(pubspec);
  if (m == null) {
    stderr.writeln("ERRO: 'version: X.Y.Z+N' não encontrado no pubspec.yaml");
    exit(1);
  }
  final v = m.group(1)!;
  File('lib/versao.dart').writeAsStringSync(
    '// GERADO AUTOMATICAMENTE — não editar à mão.\n'
    '// Fonte única: `version:` do pubspec.yaml via `dart tool/gerar_versao.dart`\n'
    '// (o CI gera a cada build; rode localmente após bumpar o pubspec).\n'
    '// Exibida no topo da tela principal (ao lado de "Taskix").\n'
    "const String appVersao = 'V$v';\n",
  );
  print('lib/versao.dart <- V$v'); // ignore: avoid_print (saída do CLI é o propósito)
}
