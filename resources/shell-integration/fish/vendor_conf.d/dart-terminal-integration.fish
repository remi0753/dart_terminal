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
    set --global --export DART_TERMINAL_SHELL_INTEGRATION_VERSION 2
    set --global --export DART_TERMINAL_SHELL_INTEGRATION_SHELL fish

    set --global __dart_terminal_command_active 0

    function __dart_terminal_report_metadata
        set --local cwd "$PWD"
        if test (string length -- "$cwd") -gt 1000
            return
        end
        if string match --quiet --regex '[[:cntrl:]]' -- "$cwd"
            return
        end

        set --local title (string replace --regex '^.*/' '' -- "$cwd")
        if test -z "$title"
            set title /
        end
        if test (string length -- "$title") -gt 256
            return
        end
        if string match --quiet --regex '[[:cntrl:]]' -- "$title"
            return
        end

        set --local uri (string replace --all '%' '%25' -- "$cwd")
        set uri (string replace --all ' ' '%20' -- "$uri")
        set uri (string replace --all '#' '%23' -- "$uri")
        set uri (string replace --all '?' '%3F' -- "$uri")
        printf '\e]7;file://localhost%s\a' "$uri"
        printf '\e]2;%s\a' "$title"
    end

    function __dart_terminal_preexec --on-event fish_preexec
        set --global __dart_terminal_command_active 1
        printf '\e]133;C\a'
    end

    function __dart_terminal_postexec --on-event fish_postexec
        printf '\e]133;D;%s\a' $status
        set --global __dart_terminal_command_active 0
    end

    function __dart_terminal_prompt --on-event fish_prompt
        if test "$__dart_terminal_command_active" = 1
            printf '\e]133;D\a'
            set --global __dart_terminal_command_active 0
        end
        __dart_terminal_report_metadata
        printf '\e]133;A\a\e]133;B\a'
    end

    function __dart_terminal_pwd --on-variable PWD
        __dart_terminal_report_metadata
    end

    __dart_terminal_report_metadata
end
