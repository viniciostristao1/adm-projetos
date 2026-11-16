/// Pontezinha de navegação (V0.1.181): permite abrir uma ABA do `HomeShell`
/// de qualquer tela (ex.: o atalho da Muse DENTRO de um projeto) sem acoplar as
/// telas ao HomeShell nem criar import circular. O `_HomeShellState` registra as
/// funções ao montar; quem quiser abrir uma aba (com a barra inferior) chama
/// `abrirAbaMuse?.call()` / `abrirAbaProjetos?.call()` depois de voltar ao shell.
library;

void Function()? abrirAbaMuse;

/// Abre a aba Projetos (ex.: botão pasta no topo do chat, que sai do chat e
/// cai na aba Projetos como o botão da barra inferior).
void Function()? abrirAbaProjetos;
