# Windows diagnostic logging

Diagnostic logs record the stage and category of a failure that blocked startup or made a long-running session unstable. They never contain user conversations.

## Write one log for each session

`StartupDiagnostics` creates logs in:

```text
%LOCALAPPDATA%\SIDEY\Logs
```

File names use this format:

```text
SIDEY.<underscore-separated version>.<yyyyMMdd>.<HHmmss>.log
```

For example, starting version `1.2.1` at 03:04:05 UTC on September 12, 2026 creates `SIDEY.1_2_1.20260912.030405.log`. All timestamps are recorded in UTC so that the user's regional settings cannot change how a log is interpreted.

If a fatal startup failure occurs, the error dialog shows the path to this log.

## Record whether the app continued after a failure

The diagnostics API records three forms that match the app's startup and shutdown flow:

- `Stage(name)` records how far startup or shutdown progressed.
- `NonFatal(stage, exception)` records a failure from which the application can continue.
- `Fatal(stage, exception, showDialog)` records a failure that prevents normal operation and opens a dialog when needed.

These forms tell a reader whether the app stopped or recovered and continued.

At the start of a session, the log records the app version, build version, OS version, OS and process architectures, .NET runtime, and processor count. It also records markers for completed startup and normal shutdown. If the previous log does not end with a normal-shutdown marker, the next startup records `previous-session-end result=unclean`.

## Log exception classifications

Exception messages can contain server responses, paths, or tokens. `StartupDiagnostics` records only the fields needed to classify the problem:

- exception type and HRESULT;
- up to eight levels of inner-exception types;
- a call stack with source paths removed;
- HTTP status code;
- DNS, socket, TLS, and timeout classifications;
- Win32 native error code; and
- for file errors, the file name rather than the full path.

Repeated failures include a `repeat` count, which tracks recurrence without storing request contents.

## Keep personal data out of logs

Never record the following values, regardless of whether an operation succeeds or fails:

- message bodies, text being typed, nicknames, or email addresses;
- access tokens, refresh tokens, credentials, or invite codes;
- raw user, room, or message UUIDs;
- keystrokes, mouse coordinates, screen contents, or active application lists;
- file contents or complete user paths; or
- user names or computer names.

When an identifier seems useful, first try a stage name, count, or state classification. Arbitrarily hashed identifiers can still correlate activity across logs, so leave them out by default.

```csharp
StartupDiagnostics.Stage("realtime-connect-start");

try
{
    await session.ConnectAsync(cancellationToken);
}
catch (HttpRequestException exception)
{
    StartupDiagnostics.NonFatal("realtime-connect", exception);
}
```

This record reveals whether connection started and the category of HTTP failure. It does not need a room ID or server response body.

## Keep logging failures away from app behavior

Log writing and retention cleanup are best-effort operations. Their own failures must not block startup or shutdown.

- A file is limited to 4 MiB. Once it reaches that limit, write one marker and discard subsequent records.
- Retain logs for no more than 30 days.
- Retain no more than 100 files or 32 MiB in total within the directory.
- Attempt cleanup at startup and every six hours while running.

While the application runs, record the working set, private bytes, managed heap size, handle count, and GDI and USER object counts every minute. These metrics help identify resources that grow continuously during a long-running session. They contain no screen or user-work contents.

After adding or changing an entry, inspect a resulting log line and trace every input that can reach it for prohibited values. Follow [`debugging-en.md`](debugging-en.md) for the debugging procedure.
