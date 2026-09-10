# Dart Terminal nushell integration resource contract version 1.

export module dart_terminal {
  export-env {
    $env.DART_TERMINAL_SHELL_INTEGRATION = "1"
    $env.DART_TERMINAL_SHELL_INTEGRATION_VERSION = "1"
    $env.DART_TERMINAL_SHELL_INTEGRATION_SHELL = "nushell"
  }
}

if 'DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR' in $env {
  if 'XDG_DATA_DIRS' in $env {
    let injected = $"($env.DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR):"
    $env.XDG_DATA_DIRS = ($env.XDG_DATA_DIRS | str replace $injected "")
  }
  hide-env DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR
}
