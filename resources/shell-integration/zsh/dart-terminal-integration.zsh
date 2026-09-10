# Dart Terminal zsh integration resource contract version 1.

[[ -o interactive ]] || return 0
(( ${+_dart_terminal_shell_integration_loaded} )) && return 0

builtin typeset -g _dart_terminal_shell_integration_loaded=1
builtin export DART_TERMINAL_SHELL_INTEGRATION=1
builtin export DART_TERMINAL_SHELL_INTEGRATION_VERSION=2
builtin export DART_TERMINAL_SHELL_INTEGRATION_SHELL=zsh

builtin typeset -gi _dart_terminal_command_active=0

function __dart_terminal_report_metadata() {
  builtin emulate -L zsh -o no_aliases
  builtin local _cwd="$PWD"
  (( ${#_cwd} <= 1000 )) || return 0
  [[ "$_cwd" != *[[:cntrl:]]* ]] || return 0

  builtin local _title="${_cwd:t}"
  [[ -n "$_title" ]] || _title=/
  (( ${#_title} <= 256 )) || return 0
  [[ "$_title" != *[[:cntrl:]]* ]] || return 0

  builtin local _uri="$_cwd"
  _uri="${_uri//\%/%25}"
  _uri="${_uri// /%20}"
  _uri="${_uri//\#/%23}"
  _uri="${_uri//\?/%3F}"
  builtin print -rn -- $'\e]7;file://localhost'"$_uri"$'\a'
  builtin print -rn -- $'\e]2;'"$_title"$'\a'
}

function __dart_terminal_precmd() {
  builtin local _status=$?
  if (( _dart_terminal_command_active )); then
    builtin print -rn -- $'\e]133;D;'"$_status"$'\a'
  fi
  __dart_terminal_report_metadata
  builtin print -rn -- $'\e]133;A\a\e]133;B\a'
  builtin typeset -gi _dart_terminal_command_active=0
}

function __dart_terminal_preexec() {
  builtin typeset -gi _dart_terminal_command_active=1
  builtin print -rn -- $'\e]133;C\a'
}

builtin autoload -Uz add-zsh-hook
add-zsh-hook precmd __dart_terminal_precmd
add-zsh-hook preexec __dart_terminal_preexec
add-zsh-hook chpwd __dart_terminal_report_metadata
__dart_terminal_report_metadata
