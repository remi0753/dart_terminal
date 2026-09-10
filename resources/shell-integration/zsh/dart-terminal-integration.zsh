# Dart Terminal zsh integration resource contract version 1.

[[ -o interactive ]] || return 0
(( ${+_dart_terminal_shell_integration_loaded} )) && return 0

builtin typeset -g _dart_terminal_shell_integration_loaded=1
builtin export DART_TERMINAL_SHELL_INTEGRATION=1
builtin export DART_TERMINAL_SHELL_INTEGRATION_VERSION=1
builtin export DART_TERMINAL_SHELL_INTEGRATION_SHELL=zsh
