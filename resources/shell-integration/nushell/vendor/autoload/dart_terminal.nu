# Dart Terminal nushell integration resource contract version 1.

export module dart_terminal {
  def report_metadata [] {
    let cwd = $env.PWD
    let cwd_clean = ($cwd | str replace --all --regex '[[:cntrl:]]' '')
    let raw_title = ($cwd | path basename)
    let title = if ($raw_title | is-empty) { '/' } else { $raw_title }
    let title_clean = ($title | str replace --all --regex '[[:cntrl:]]' '')
    if (
      ($cwd | str length --utf-8-bytes) <= 1000 and
      ($title | str length --utf-8-bytes) <= 256 and
      $cwd_clean == $cwd and
      $title_clean == $title
    ) {
      let uri = (
        $cwd
        | str replace --all '%' '%25'
        | str replace --all ' ' '%20'
        | str replace --all '#' '%23'
        | str replace --all '?' '%3F'
      )
      print --no-newline $"\u{1b}]7;file://localhost($uri)\u{7}"
      print --no-newline $"\u{1b}]2;($title)\u{7}"
    }
  }

  export-env {
    if 'DART_TERMINAL_SHELL_INTEGRATION' not-in $env {
      $env.DART_TERMINAL_SHELL_INTEGRATION = "1"
      $env.DART_TERMINAL_SHELL_INTEGRATION_VERSION = "2"
      $env.DART_TERMINAL_SHELL_INTEGRATION_SHELL = "nushell"

      let pre_prompt = (
        $env.config
        | get --optional hooks.pre_prompt
        | default []
        | append {||
            print --no-newline "\u{1b}]133;D\u{7}"
            report_metadata
            print --no-newline "\u{1b}]133;A\u{7}\u{1b}]133;B\u{7}"
          }
      )
      let pre_execution = (
        $env.config
        | get --optional hooks.pre_execution
        | default []
        | append {|| print --no-newline "\u{1b}]133;C\u{7}" }
      )
      let pwd_change = (
        $env.config
        | get --optional hooks.env_change.PWD
        | default []
        | append {|_, _| report_metadata }
      )
      $env.config = (
        $env.config
        | upsert hooks.pre_prompt $pre_prompt
        | upsert hooks.pre_execution $pre_execution
        | upsert hooks.env_change.PWD $pwd_change
      )
      report_metadata
    }
  }
}

if 'DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR' in $env {
  if 'XDG_DATA_DIRS' in $env {
    let injected = $"($env.DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR):"
    $env.XDG_DATA_DIRS = ($env.XDG_DATA_DIRS | str replace $injected "")
  }
  hide-env DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR
}
