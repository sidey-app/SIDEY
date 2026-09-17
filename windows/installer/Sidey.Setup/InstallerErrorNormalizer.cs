using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace Sidey.Setup.Errors
{
    public static class Program
    {
        private const int InvalidArguments = 64;

        [STAThread]
        public static int Main(string[] arguments)
        {
            CommandLine commandLine = null;
            try
            {
                commandLine = CommandLine.Parse(arguments);
                string resultPath = commandLine.OptionalValue("--result-path");
                string logPath = commandLine.OptionalValue("--log-path");
                string installerVersion = commandLine.OptionalValue("--installer-version") ?? "unknown";

                if (commandLine.HasFlag("--normalize-error"))
                {
                    commandLine.AssertOnlyModeFlags("--normalize-error");
                    InstallerResult normalized = InstallerErrors.CreateResult(
                        commandLine.RequiredValue("--native-code"),
                        commandLine.OptionalValue("--source") ?? "UNKNOWN",
                        commandLine.OptionalValue("--stage") ?? "INSTALL",
                        commandLine.OptionalValue("--category-hint"),
                        commandLine.OptionalValue("--target"),
                        commandLine.OptionalValue("--command-description"),
                        commandLine.OptionalValue("--exit-code"),
                        commandLine.OptionalValue("--message"),
                        installerVersion);
                    ResultWriter.Write(normalized, resultPath, logPath);
                    return 0;
                }

                throw new CommandLineException("Unsupported helper mode.");
            }
            catch (CommandLineException exception)
            {
                Console.Error.WriteLine(exception.Message);
                return InvalidArguments;
            }
            catch (Exception exception)
            {
                string resultPath = commandLine == null
                    ? CommandLine.FindRawValue(arguments, "--result-path")
                    : commandLine.OptionalValue("--result-path");
                string logPath = commandLine == null
                    ? CommandLine.FindRawValue(arguments, "--log-path")
                    : commandLine.OptionalValue("--log-path");
                string installerVersion = commandLine == null
                    ? CommandLine.FindRawValue(arguments, "--installer-version") ?? "unknown"
                    : commandLine.OptionalValue("--installer-version") ?? "unknown";
                InstallerResult failure = InstallerErrors.FromException(exception, installerVersion);
                try
                {
                    ResultWriter.Write(failure, resultPath, logPath);
                }
                catch
                {
                    // Reporting must never replace the original installer failure.
                }
                Console.Error.WriteLine(
                    "Installer error: " + failure.Category + " (" + failure.NativeCode + ")");
                return 1;
            }
        }
    }

    internal sealed class CommandLineException : Exception
    {
        internal CommandLineException(string message) : base(message) { }
    }

    internal sealed class CommandLine
    {
        private static readonly HashSet<string> FlagNames = new HashSet<string>(
            new[]
            {
                "--normalize-error",
            },
            StringComparer.OrdinalIgnoreCase);

        private static readonly HashSet<string> ValueNames = new HashSet<string>(
            new[]
            {
                "--result-path",
                "--log-path",
                "--installer-version",
                "--native-code",
                "--source",
                "--stage",
                "--category-hint",
                "--target",
                "--command-description",
                "--exit-code",
                "--message",
            },
            StringComparer.OrdinalIgnoreCase);

        private readonly HashSet<string> flags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, string> values =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        internal static CommandLine Parse(string[] arguments)
        {
            var parsed = new CommandLine();
            for (int index = 0; index < arguments.Length; index++)
            {
                string argument = arguments[index];
                if (FlagNames.Contains(argument))
                {
                    if (!parsed.flags.Add(argument))
                    {
                        throw new CommandLineException("Duplicate argument: " + argument);
                    }
                    continue;
                }
                if (!ValueNames.Contains(argument))
                {
                    throw new CommandLineException("Unsupported argument: " + argument);
                }
                if (parsed.values.ContainsKey(argument))
                {
                    throw new CommandLineException("Duplicate argument: " + argument);
                }
                if (++index >= arguments.Length || arguments[index].StartsWith("--", StringComparison.Ordinal))
                {
                    throw new CommandLineException("Missing value for argument: " + argument);
                }
                parsed.values.Add(argument, arguments[index]);
            }

            return parsed;
        }

        internal static string FindRawValue(string[] arguments, string name)
        {
            for (int index = 0; index + 1 < arguments.Length; index++)
            {
                if (string.Equals(arguments[index], name, StringComparison.OrdinalIgnoreCase))
                {
                    return arguments[index + 1];
                }
            }
            return null;
        }

        internal bool HasFlag(string name)
        {
            return flags.Contains(name);
        }

        internal string OptionalValue(string name)
        {
            string value;
            return values.TryGetValue(name, out value) ? value : null;
        }

        internal string RequiredValue(string name)
        {
            string value = OptionalValue(name);
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new CommandLineException("Required argument is missing: " + name);
            }
            return value;
        }

        internal void AssertOnlyModeFlags(string selectedMode)
        {
            foreach (string flag in flags)
            {
                if (!string.Equals(flag, selectedMode, StringComparison.OrdinalIgnoreCase))
                {
                    throw new CommandLineException(
                        flag + " cannot be combined with " + selectedMode + ".");
                }
            }
        }
    }

    internal sealed class InstallerFailureException : Exception
    {
        internal InstallerFailureException(
            string message,
            Exception innerException,
            object nativeCode,
            string source,
            string stage,
            string categoryHint,
            string target,
            string commandDescription,
            string exitCode,
            string symbol)
            : base(message, innerException)
        {
            NativeCode = nativeCode;
            SourceName = source;
            Stage = stage;
            CategoryHint = categoryHint;
            Target = target;
            CommandDescription = commandDescription;
            ExitCode = exitCode;
            Symbol = symbol;
        }

        internal object NativeCode { get; private set; }
        internal string SourceName { get; private set; }
        internal string Stage { get; private set; }
        internal string CategoryHint { get; private set; }
        internal string Target { get; private set; }
        internal string CommandDescription { get; private set; }
        internal string ExitCode { get; private set; }
        internal string Symbol { get; private set; }
    }

    internal sealed class InstallerResult
    {
        internal string Status;
        internal string Category;
        internal string NativeCode;
        internal string Source;
        internal string Stage;
        internal string Symbol;
        internal string Message;
        internal string Target;
        internal string CommandDescription;
        internal string ExitCode;
        internal string InstallerVersion;
    }

    internal static class InstallerErrors
    {
        private sealed class ErrorDefinition
        {
            internal ErrorDefinition(string category, string symbol)
            {
                Category = category;
                Symbol = symbol;
            }

            internal string Category;
            internal string Symbol;
        }

        private static readonly HashSet<string> Categories = new HashSet<string>(
            new[]
            {
                "NETWORK_ERROR", "DOWNLOAD_FAILED", "DISK_FULL", "PERMISSION_DENIED",
                "BLOCKED_BY_POLICY", "PACKAGE_CORRUPTED", "SIGNATURE_ERROR",
                "DEPENDENCY_MISSING", "DEPENDENCY_CONFLICT", "INCOMPATIBLE_SYSTEM",
                "APP_IN_USE", "ANOTHER_INSTALLATION_RUNNING", "ALREADY_INSTALLED",
                "REBOOT_REQUIRED", "USER_CANCELLED", "PACKAGE_REGISTRATION_FAILED",
                "PACKAGE_REPOSITORY_CORRUPTED", "UNKNOWN_ERROR",
            },
            StringComparer.Ordinal);

        private static readonly Dictionary<string, ErrorDefinition> Definitions =
            CreateDefinitions();

        private static Dictionary<string, ErrorDefinition> CreateDefinitions()
        {
            var definitions = new Dictionary<string, ErrorDefinition>(StringComparer.OrdinalIgnoreCase);
            Add(definitions, "0x80073CF0", "PACKAGE_CORRUPTED", "ERROR_INSTALL_OPEN_PACKAGE_FAILED");
            Add(definitions, "0x80073CF3", "DEPENDENCY_CONFLICT", "ERROR_INSTALL_RESOLVE_DEPENDENCY_FAILED");
            Add(definitions, "0x80073CF4", "DISK_FULL", "ERROR_INSTALL_OUT_OF_DISK_SPACE");
            Add(definitions, "0x80073CF5", "DOWNLOAD_FAILED", "ERROR_INSTALL_NETWORK_FAILURE");
            Add(definitions, "0x80073CF6", "PACKAGE_REGISTRATION_FAILED", "ERROR_INSTALL_REGISTRATION_FAILURE");
            Add(definitions, "0x80073CF9", "UNKNOWN_ERROR", "ERROR_INSTALL_FAILED");
            Add(definitions, "0x80073CFB", "ALREADY_INSTALLED", "ERROR_PACKAGE_ALREADY_EXISTS");
            Add(definitions, "0x80073CFD", "DEPENDENCY_MISSING", "ERROR_INSTALL_PREREQUISITE_FAILED");
            Add(definitions, "0x80073CFE", "PACKAGE_REPOSITORY_CORRUPTED", "ERROR_PACKAGE_REPOSITORY_CORRUPTED");
            Add(definitions, "0x80073CFF", "BLOCKED_BY_POLICY", "ERROR_INSTALL_POLICY_FAILURE");
            Add(definitions, "0x80073D01", "BLOCKED_BY_POLICY", "ERROR_DEPLOYMENT_BLOCKED_BY_POLICY");
            Add(definitions, "0x80073D02", "APP_IN_USE", "ERROR_PACKAGES_IN_USE");
            Add(definitions, "0x80073D06", "ALREADY_INSTALLED", "ERROR_INSTALL_PACKAGE_DOWNGRADE");
            Add(definitions, "0x80073D10", "INCOMPATIBLE_SYSTEM", "ERROR_INSTALL_WRONG_PROCESSOR_ARCHITECTURE");
            Add(definitions, "0x80073D28", "PERMISSION_DENIED", "ERROR_PACKAGED_SERVICE_REQUIRES_ADMIN_PRIVILEGES");
            Add(definitions, "0x80080203", "PACKAGE_CORRUPTED", "APPX_E_MISSING_REQUIRED_FILE");
            Add(definitions, "0x80080206", "PACKAGE_CORRUPTED", "APPX_E_CORRUPT_CONTENT");
            Add(definitions, "0x80080207", "PACKAGE_CORRUPTED", "APPX_E_BLOCK_HASH_INVALID");
            Add(definitions, "0x800B0100", "SIGNATURE_ERROR", "TRUST_E_NOSIGNATURE");
            Add(definitions, "0x800B0109", "SIGNATURE_ERROR", "CERT_E_UNTRUSTEDROOT");
            Add(definitions, "0x80070005", "PERMISSION_DENIED", "E_ACCESSDENIED");
            Add(definitions, "0x80070070", "DISK_FULL", "ERROR_DISK_FULL");
            Add(definitions, "5", "PERMISSION_DENIED", "ERROR_ACCESS_DENIED");
            Add(definitions, "1300", "PERMISSION_DENIED", "ERROR_NOT_ALL_ASSIGNED");
            Add(definitions, "1314", "PERMISSION_DENIED", "ERROR_PRIVILEGE_NOT_HELD");
            Add(definitions, "12002", "NETWORK_ERROR", "ERROR_INTERNET_TIMEOUT");
            Add(definitions, "12007", "NETWORK_ERROR", "ERROR_INTERNET_NAME_NOT_RESOLVED");
            Add(definitions, "12029", "NETWORK_ERROR", "ERROR_INTERNET_CANNOT_CONNECT");
            Add(definitions, "12030", "NETWORK_ERROR", "ERROR_INTERNET_CONNECTION_ABORTED");
            Add(definitions, "12031", "NETWORK_ERROR", "ERROR_INTERNET_CONNECTION_RESET");
            Add(definitions, "12163", "NETWORK_ERROR", "ERROR_INTERNET_DISCONNECTED");
            Add(definitions, "1602", "USER_CANCELLED", "ERROR_INSTALL_USEREXIT");
            Add(definitions, "1603", "UNKNOWN_ERROR", "ERROR_INSTALL_FAILURE");
            Add(definitions, "1618", "ANOTHER_INSTALLATION_RUNNING", "ERROR_INSTALL_ALREADY_RUNNING");
            Add(definitions, "1619", "PACKAGE_CORRUPTED", "ERROR_INSTALL_PACKAGE_OPEN_FAILED");
            Add(definitions, "1620", "PACKAGE_CORRUPTED", "ERROR_INSTALL_PACKAGE_INVALID");
            Add(definitions, "1625", "BLOCKED_BY_POLICY", "ERROR_INSTALL_PACKAGE_REJECTED");
            Add(definitions, "1633", "INCOMPATIBLE_SYSTEM", "ERROR_INSTALL_PLATFORM_UNSUPPORTED");
            Add(definitions, "1638", "ALREADY_INSTALLED", "ERROR_PRODUCT_VERSION");
            return definitions;
        }

        private static void Add(
            IDictionary<string, ErrorDefinition> definitions,
            string code,
            string category,
            string symbol)
        {
            definitions.Add(code, new ErrorDefinition(category, symbol));
        }

        internal static string NormalizeNativeCode(object nativeCode)
        {
            if (nativeCode == null || string.IsNullOrWhiteSpace(Convert.ToString(nativeCode, CultureInfo.InvariantCulture)))
            {
                return "UNKNOWN";
            }
            string text = Convert.ToString(nativeCode, CultureInfo.InvariantCulture).Trim();
            Match hexadecimal = Regex.Match(text, "^0[xX](?<hex>[0-9a-fA-F]{1,8})$");
            if (hexadecimal.Success)
            {
                uint value = uint.Parse(
                    hexadecimal.Groups["hex"].Value,
                    NumberStyles.HexNumber,
                    CultureInfo.InvariantCulture);
                return "0x" + value.ToString("X8", CultureInfo.InvariantCulture);
            }

            long number;
            if (!long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out number))
            {
                return text;
            }
            if (number < 0 && number >= int.MinValue)
            {
                return "0x" + unchecked((uint)(int)number).ToString("X8", CultureInfo.InvariantCulture);
            }
            if (number > int.MaxValue && number <= uint.MaxValue)
            {
                return "0x" + ((uint)number).ToString("X8", CultureInfo.InvariantCulture);
            }
            return number.ToString(CultureInfo.InvariantCulture);
        }

        internal static InstallerResult CreateResult(
            object nativeCode,
            string source,
            string stage,
            string categoryHint,
            string target,
            string commandDescription,
            string exitCode,
            string message,
            string installerVersion)
        {
            string normalizedCode = NormalizeNativeCode(nativeCode);
            string status;
            string category;
            string symbol;
            if (normalizedCode == "0" || normalizedCode == "0x00000000")
            {
                status = "SUCCESS";
                category = string.Empty;
                symbol = "ERROR_SUCCESS";
            }
            else if (normalizedCode == "1641" || normalizedCode == "3010")
            {
                status = "SUCCESS_REBOOT_REQUIRED";
                category = "REBOOT_REQUIRED";
                symbol = normalizedCode == "1641"
                    ? "ERROR_SUCCESS_REBOOT_INITIATED"
                    : "ERROR_SUCCESS_REBOOT_REQUIRED";
            }
            else
            {
                status = "FAILED";
                ErrorDefinition definition;
                if (Definitions.TryGetValue(normalizedCode, out definition))
                {
                    category = definition.Category;
                    symbol = definition.Symbol;
                }
                else
                {
                    category = !string.IsNullOrEmpty(categoryHint) && Categories.Contains(categoryHint)
                        ? categoryHint
                        : string.Equals(stage, "DOWNLOAD", StringComparison.Ordinal)
                            ? "DOWNLOAD_FAILED"
                            : "UNKNOWN_ERROR";
                    symbol = string.Empty;
                }
            }

            return new InstallerResult
            {
                Status = status,
                Category = category,
                NativeCode = normalizedCode,
                Source = source,
                Stage = stage,
                Symbol = symbol,
                Message = message,
                Target = target,
                CommandDescription = commandDescription,
                ExitCode = exitCode,
                InstallerVersion = installerVersion,
            };
        }

        internal static InstallerResult FromException(Exception exception, string installerVersion)
        {
            exception = Unwrap(exception);
            InstallerFailureException failure = FindInstallerFailure(exception);
            object nativeCode = failure == null || failure.NativeCode == null
                ? FindNativeCode(exception)
                : failure.NativeCode;
            string source = failure == null || string.IsNullOrWhiteSpace(failure.SourceName)
                ? "MANAGED_HELPER"
                : failure.SourceName;
            string stage = failure == null || string.IsNullOrWhiteSpace(failure.Stage)
                ? "INSTALL"
                : failure.Stage;
            InstallerResult result = CreateResult(
                nativeCode,
                source,
                stage,
                failure == null ? null : failure.CategoryHint,
                failure == null ? null : failure.Target,
                failure == null ? null : failure.CommandDescription,
                failure == null ? null : failure.ExitCode,
                exception.Message,
                installerVersion);
            if (failure != null && string.IsNullOrEmpty(result.Symbol) && !string.IsNullOrEmpty(failure.Symbol))
            {
                result.Symbol = failure.Symbol;
            }
            return result;
        }

        private static Exception Unwrap(Exception exception)
        {
            while ((exception is TargetInvocationException || exception is AggregateException)
                && exception.InnerException != null)
            {
                exception = exception.InnerException;
            }
            return exception;
        }

        private static InstallerFailureException FindInstallerFailure(Exception exception)
        {
            while (exception != null)
            {
                InstallerFailureException failure = exception as InstallerFailureException;
                if (failure != null)
                {
                    return failure;
                }
                exception = exception.InnerException;
            }
            return null;
        }

        private static object FindNativeCode(Exception exception)
        {
            object fallback = null;
            while (exception != null)
            {
                Win32Exception win32 = exception as Win32Exception;
                if (win32 != null && win32.NativeErrorCode != 0)
                {
                    return win32.NativeErrorCode;
                }
                if (exception.HResult != 0)
                {
                    fallback = exception.HResult;
                }
                exception = exception.InnerException;
            }
            return fallback;
        }

        internal static string DownloadCategory(Exception exception)
        {
            while (exception != null)
            {
                WebException web = exception as WebException;
                if (web != null)
                {
                    switch (web.Status)
                    {
                        case WebExceptionStatus.ConnectFailure:
                        case WebExceptionStatus.ConnectionClosed:
                        case WebExceptionStatus.KeepAliveFailure:
                        case WebExceptionStatus.NameResolutionFailure:
                        case WebExceptionStatus.ProxyNameResolutionFailure:
                        case WebExceptionStatus.ReceiveFailure:
                        case WebExceptionStatus.SendFailure:
                        case WebExceptionStatus.Timeout:
                            return "NETWORK_ERROR";
                    }
                }
                exception = exception.InnerException;
            }
            return "DOWNLOAD_FAILED";
        }
    }

    internal static class ResultWriter
    {
        internal static void Write(InstallerResult result, string resultPath, string logPath)
        {
            if (!string.IsNullOrWhiteSpace(resultPath))
            {
                EnsureParent(resultPath);
                string[] lines =
                {
                    "[InstallerResult]",
                    "status=" + Safe(result.Status),
                    "category=" + Safe(result.Category),
                    "source=" + Safe(result.Source),
                    "nativeCode=" + Safe(result.NativeCode),
                    "stage=" + Safe(result.Stage),
                    "symbol=" + Safe(result.Symbol),
                    "detail=" + Safe(result.Message),
                    "target=" + Safe(result.Target),
                    "command=" + Safe(result.CommandDescription),
                    "exitCode=" + Safe(result.ExitCode),
                    "logPath=" + Safe(logPath),
                };
                File.WriteAllLines(resultPath, lines, Encoding.Unicode);
            }

            try
            {
                AppendLog(result, logPath);
            }
            catch
            {
                // Diagnostics are best-effort and cannot change the operation result.
            }
        }

        internal static void AppendWarning(string logPath, string warning)
        {
            if (string.IsNullOrWhiteSpace(logPath))
            {
                return;
            }
            try
            {
                EnsureParent(logPath);
                using (var writer = new StreamWriter(logPath, true, new UTF8Encoding(true)))
                {
                    writer.WriteLine("[InstallerWarning]");
                    writer.WriteLine("timestamp=" + DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture));
                    writer.WriteLine("detail=" + Safe(warning));
                    writer.WriteLine();
                }
            }
            catch
            {
                // A diagnostic warning must never replace the operation result.
            }
        }

        private static void AppendLog(InstallerResult result, string logPath)
        {
            if (string.IsNullOrWhiteSpace(logPath))
            {
                return;
            }
            EnsureParent(logPath);
            using (var writer = new StreamWriter(logPath, true, new UTF8Encoding(true)))
            {
                writer.WriteLine(result.Status == "FAILED" ? "[InstallerError]" : "[InstallerResult]");
                writer.WriteLine("timestamp=" + DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture));
                writer.WriteLine("status=" + Safe(result.Status));
                writer.WriteLine("category=" + Safe(result.Category));
                writer.WriteLine("source=" + Safe(result.Source));
                writer.WriteLine("nativeCode=" + Safe(result.NativeCode));
                writer.WriteLine("stage=" + Safe(result.Stage));
                writer.WriteLine("message=" + Safe(result.Symbol));
                writer.WriteLine("detail=" + Safe(result.Message));
                writer.WriteLine("target=" + Safe(result.Target));
                writer.WriteLine("command=" + Safe(result.CommandDescription));
                writer.WriteLine("exitCode=" + Safe(result.ExitCode));
                writer.WriteLine("windowsVersion=" + Safe(Environment.OSVersion.VersionString));
                writer.WriteLine("installerVersion=" + Safe(result.InstallerVersion));
                writer.WriteLine();
            }
        }

        private static void EnsureParent(string path)
        {
            string directory = Path.GetDirectoryName(Path.GetFullPath(path));
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }
        }

        internal static string Safe(object value)
        {
            string text = value == null ? string.Empty : Convert.ToString(value, CultureInfo.InvariantCulture);
            text = Regex.Replace(text, "[\\r\\n\\t]+", " ");
            text = ReplacePath(text, Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "%USERPROFILE%");
            text = ReplacePath(text, Path.GetTempPath().TrimEnd('\\'), "%TEMP%");
            text = Regex.Replace(
                text,
                "https://[^\\s?]+\\?[^\\s]+",
                delegate(Match match)
                {
                    Uri uri;
                    return Uri.TryCreate(match.Value, UriKind.Absolute, out uri)
                        ? uri.GetLeftPart(UriPartial.Path)
                        : "https://[redacted]";
                },
                RegexOptions.IgnoreCase);
            return text.Length > 1000 ? text.Substring(0, 1000) : text;
        }

        private static string ReplacePath(string text, string path, string replacement)
        {
            return string.IsNullOrWhiteSpace(path)
                ? text
                : Regex.Replace(text, Regex.Escape(path), replacement, RegexOptions.IgnoreCase);
        }
    }
}
