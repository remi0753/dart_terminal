/// Test seams for the terminal AppleScript native capability.
library;

export 'src/api.dart'
    show
        TerminalAppleScriptMacosCommandDisposition,
        TerminalAppleScriptMacosException,
        TerminalAppleScriptMacosLimits,
        TerminalAppleScriptMacosSession,
        TerminalAppleScriptMacosSummary;
export 'src/native_backend.dart'
    show
        TerminalAppleScriptMacosBindings,
        TerminalAppleScriptMacosSelfAutomation,
        TerminalAppleScriptMacosTakeResult;
