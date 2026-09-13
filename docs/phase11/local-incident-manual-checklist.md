# Local incident diagnostics manual checklist

This optional checklist verifies the visible macOS presentation of the local
crash-report and hang-sample workflow. The deterministic automated acceptance
uses isolated fixtures in both runtime modes and is the completion authority;
no real crash, personal DiagnosticReports scan, long-running sample, or upload
is required.

## Privacy precautions

- Use a disposable local folder and do not attach or publish any produced
  `.ips` or `.sample.txt` file as part of this check.
- Treat either raw artifact as sensitive. It may contain stack traces,
  usernames, process/binary information, and file paths.
- Do not alter macOS privacy protections or run Dart Terminal with elevated
  privileges if report access or sampling is denied.

## Warning and cancellation

1. Open **File > Export Latest Crash Report…**.
2. Confirm that the Save panel warns that the raw report can contain stack
   traces, file paths, and process details, and that its affirmative button is
   **Save and Continue**.
3. Cancel. Confirm that no status window or destination file appears.
4. Repeat for **File > Capture Hang Sample…**. Confirm that the warning names
   the current Dart Terminal and the fixed one-second capture, then cancel.

Both actions should also be searchable in the Command Palette and should have
no default shortcut.

## Optional local artifact check

Only if knowingly authorized, choose a disposable destination for either
action. A successful operation should open or reuse one read-only **Local
Incident Diagnostics** window. It must show only a fixed status plus matching,
completed, and failure counts—never a source/destination path, PID, timestamp,
stack, filename, or artifact content. Escape closes the window and restores
typing focus to the active terminal.

The crash action may report not found or unavailable when macOS has no exact
product report or denies access. The sample action may report failure when
macOS denies process inspection. These fixed outcomes are valid and must not
weaken OS policy.

## Cleanup

- Delete any disposable raw artifact after inspection.
- Verify that no network or upload prompt was shown.
- Long-duration sampling, 24/72-hour soak, and intentional real crashes are
  deliberately excluded from this checklist and do not block this feature.
