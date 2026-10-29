/// Pontezinha de navegação (V0.1.181): permite abrir a ABA Muse do `HomeShell`
/// de qualquer tela (ex.: o atalho da Muse DENTRO de um projeto) sem acoplar as
/// telas ao HomeShell nem criar import circular. O `_HomeShellState` registra a
/// função ao montar; quem quiser abrir a aba Muse (com a barra inferior) chama
/// `abrirAbaMuse?.call()` depois de voltar ao shell.
library;

void Function()? abrirAbaMuse;
