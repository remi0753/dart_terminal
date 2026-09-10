# Dart Terminal bash integration resource contract version 1.

case "$-" in
  *i*) ;;
  *) return 0 ;;
esac

# ENV is used only for the automatic POSIX bootstrap. Restore it before any
# user startup file is evaluated, then return to Bash's ordinary mode.
if [ "${DART_TERMINAL_BASH_INJECT-}" = 1 ]; then
  builtin unset ENV DART_TERMINAL_BASH_INJECT
  if [ "${DART_TERMINAL_BASH_ENV_SET-}" = 1 ]; then
    builtin export ENV="${DART_TERMINAL_BASH_ENV-}"
  fi
  builtin unset DART_TERMINAL_BASH_ENV_SET DART_TERMINAL_BASH_ENV
  builtin set +o posix
  builtin shopt -u inherit_errexit 2>/dev/null || true

  if [ "${DART_TERMINAL_BASH_HISTFILE_WAS_UNSET-}" = 1 ]; then
    if [ -n "${HOME-}" ]; then
      HISTFILE="$HOME/.bash_history"
      builtin export -n HISTFILE 2>/dev/null || true
    fi
  fi
  builtin unset DART_TERMINAL_BASH_HISTFILE_WAS_UNSET

  if builtin shopt -q login_shell; then
    [ ! -r /etc/profile ] || builtin source /etc/profile
    for _dart_terminal_bash_profile in \
      "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -r "$_dart_terminal_bash_profile" ]; then
        builtin source "$_dart_terminal_bash_profile"
        break
      fi
    done
  else
    [ ! -r "$HOME/.bashrc" ] || builtin source "$HOME/.bashrc"
  fi
  builtin unset _dart_terminal_bash_profile
fi

if [ -z "${_DART_TERMINAL_SHELL_INTEGRATION_LOADED+x}" ]; then
  _DART_TERMINAL_SHELL_INTEGRATION_LOADED=1
  builtin export DART_TERMINAL_SHELL_INTEGRATION=1
  builtin export DART_TERMINAL_SHELL_INTEGRATION_VERSION=2
  builtin export DART_TERMINAL_SHELL_INTEGRATION_SHELL=bash

  __dart_terminal_report_metadata() {
    local _cwd="${PWD-}"
    [ "${#_cwd}" -le 1000 ] || return 0
    case "$_cwd" in
      *[[:cntrl:]]*) return 0 ;;
    esac

    local _title="${_cwd##*/}"
    [ -n "$_title" ] || _title=/
    [ "${#_title}" -le 256 ] || return 0
    case "$_title" in
      *[[:cntrl:]]*) return 0 ;;
    esac

    local _uri="$_cwd"
    _uri="${_uri//\%/%25}"
    _uri="${_uri// /%20}"
    _uri="${_uri//\#/%23}"
    _uri="${_uri//\?/%3F}"
    builtin printf '\e]7;file://localhost%s\a' "$_uri"
    builtin printf '\e]2;%s\a' "$_title"
  }

  __dart_terminal_prompt_command() {
    builtin printf '\e]133;D\a'
    __dart_terminal_report_metadata
    builtin printf '\e]133;A\a\e]133;B\a'
  }

  # Bash 4.4 and later expand PS0 immediately before executing each command.
  # Preserve a user-owned value after the fixed, content-free marker.
  PS0=$'\e]133;C\a'"${PS0-}"
  case "$(builtin declare -p PROMPT_COMMAND 2>/dev/null)" in
    'declare -a '*)
      PROMPT_COMMAND+=(__dart_terminal_prompt_command)
      ;;
    *)
      if [ -n "${PROMPT_COMMAND-}" ]; then
        PROMPT_COMMAND="${PROMPT_COMMAND%;};__dart_terminal_prompt_command"
      else
        PROMPT_COMMAND=__dart_terminal_prompt_command
      fi
      ;;
  esac
  __dart_terminal_report_metadata
fi
