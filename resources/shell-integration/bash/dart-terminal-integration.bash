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
  builtin export DART_TERMINAL_SHELL_INTEGRATION_VERSION=1
  builtin export DART_TERMINAL_SHELL_INTEGRATION_SHELL=bash
fi
