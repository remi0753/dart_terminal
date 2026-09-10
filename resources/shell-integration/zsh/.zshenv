# Dart Terminal zsh bootstrap resource contract version 1.

# Restore the user's startup directory before loading any user-owned file.
if [[ "${DART_TERMINAL_ZDOTDIR_SET-}" == 1 ]]; then
  builtin export ZDOTDIR="${DART_TERMINAL_ZDOTDIR-}"
else
  builtin unset ZDOTDIR
fi
builtin unset DART_TERMINAL_ZDOTDIR_SET DART_TERMINAL_ZDOTDIR

# Match zsh's normal .zshenv lookup, then load our independent integration.
builtin typeset _dart_terminal_user_zshenv="${ZDOTDIR-$HOME}/.zshenv"
if [[ -r "$_dart_terminal_user_zshenv" &&
      "${_dart_terminal_user_zshenv:A}" != "${${(%):-%x}:A}" ]]; then
  builtin source -- "$_dart_terminal_user_zshenv"
fi
builtin unset _dart_terminal_user_zshenv

if [[ -o interactive ]]; then
  builtin source -- "${${(%):-%x}:A:h}/dart-terminal-integration.zsh"
fi
