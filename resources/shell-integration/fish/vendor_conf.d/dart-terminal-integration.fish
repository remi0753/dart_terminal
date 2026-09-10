# Dart Terminal fish integration resource contract version 1.

function __dart_terminal_restore_xdg_data_dirs
    if not set -q DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR
        return
    end
    set --local integration_root "$DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR"
    set --local retained
    if set -q XDG_DATA_DIRS
        for entry in (string split : -- "$XDG_DATA_DIRS")
            if test "$entry" != "$integration_root"
                set --append retained "$entry"
            end
        end
        if test (count $retained) -gt 0
            set --global --export XDG_DATA_DIRS (string join : -- $retained)
        else
            set --erase XDG_DATA_DIRS
        end
    end
    set --erase DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR
end

__dart_terminal_restore_xdg_data_dirs
functions --erase __dart_terminal_restore_xdg_data_dirs

status --is-interactive; or return 0
if not set -q __dart_terminal_shell_integration_loaded
    set --global __dart_terminal_shell_integration_loaded 1
    set --global --export DART_TERMINAL_SHELL_INTEGRATION 1
    set --global --export DART_TERMINAL_SHELL_INTEGRATION_VERSION 1
    set --global --export DART_TERMINAL_SHELL_INTEGRATION_SHELL fish
end
