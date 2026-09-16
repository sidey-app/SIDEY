using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;

namespace Sidey.Setup.Prerequisites
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

                if (commandLine.HasFlag("--cleanup-private-runtime"))
                {
                    commandLine.AssertOnlyModeFlags("--cleanup-private-runtime");
                    string installDirectory = commandLine.RequiredValue("--install-directory");
                    PrivateRuntimeCleanup.Remove(installDirectory);
                    InstallerResult cleanupResult = InstallerErrors.CreateResult(
                        "0",
                        "FILESYSTEM",
                        "CLEANUP",
                        null,
                        "SIDEY private Runtime",
                        "Remove-SideyPrivateRuntime",
                        "0",
                        null,
                        installerVersion);
                    ResultWriter.Write(cleanupResult, resultPath, logPath);
                    return 0;
                }

                string configurationPath = commandLine.RequiredValue("--config");
                string downloadDirectory = commandLine.OptionalValue("--download-directory");
                if (string.IsNullOrWhiteSpace(downloadDirectory))
                {
                    downloadDirectory = AppDomain.CurrentDomain.BaseDirectory;
                }

                PlatformSupport.AssertSupported();

                PrerequisiteConfiguration configuration =
                    PrerequisiteConfiguration.Load(configurationPath);
                int code = PrerequisiteService.Ensure(
                    configuration,
                    downloadDirectory,
                    commandLine.HasFlag("--check-only"),
                    commandLine.OptionalValue("--desktop-user-runner"),
                    delegate(string warning) { ResultWriter.AppendWarning(logPath, warning); });
                InstallerResult result = InstallerErrors.CreateResult(
                    code.ToString(CultureInfo.InvariantCulture),
                    "PREREQUISITE",
                    "INSTALL",
                    null,
                    "SIDEY required runtimes",
                    "Install-SideyPrerequisites",
                    code.ToString(CultureInfo.InvariantCulture),
                    null,
                    installerVersion);
                ResultWriter.Write(result, resultPath, logPath);
                return code;
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
                "--check-only",
                "--normalize-error",
                "--cleanup-private-runtime",
            },
            StringComparer.OrdinalIgnoreCase);

        private static readonly HashSet<string> ValueNames = new HashSet<string>(
            new[]
            {
                "--config",
                "--download-directory",
                "--desktop-user-runner",
                "--result-path",
                "--log-path",
                "--installer-version",
                "--install-directory",
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

            if (parsed.HasFlag("--normalize-error") && parsed.HasFlag("--cleanup-private-runtime"))
            {
                throw new CommandLineException("Only one helper mode may be selected.");
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
                writer.WriteLine("windowsVersion=" + Safe(PlatformSupport.GetActualVersionString()));
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

    internal sealed class PrerequisiteConfiguration
    {
        internal RuntimeRequirement VisualCpp;
        internal RuntimeRequirement DotNet;
        internal WindowsAppRuntimeRequirement WindowsAppRuntime;

        internal static PrerequisiteConfiguration Load(string path)
        {
            string fullPath = Path.GetFullPath(path);
            if (!File.Exists(fullPath))
            {
                throw new FileNotFoundException("Prerequisite configuration was not found.", fullPath);
            }
            object parsed = MiniJson.Parse(File.ReadAllText(fullPath, Encoding.UTF8));
            IDictionary<string, object> root = RequireObject(parsed, "root");
            RuntimeRequirement visualCpp = ReadRuntime(root, "visualCpp");
            RuntimeRequirement dotNet = ReadRuntime(root, "dotnet");
            IDictionary<string, object> appObject = RequireObject(
                RequireProperty(root, "windowsAppRuntime"),
                "windowsAppRuntime");
            var app = new WindowsAppRuntimeRequirement
            {
                MinimumVersion = ReadVersion(appObject, "sdkVersion"),
                DownloadUri = ReadUri(appObject, "url"),
                Packages = new List<PackageRequirement>(),
            };
            IList<object> packages = RequireArray(RequireProperty(appObject, "packages"), "packages");
            if (packages.Count == 0)
            {
                throw new FormatException("windowsAppRuntime.packages must not be empty.");
            }
            foreach (object value in packages)
            {
                IDictionary<string, object> package = RequireObject(value, "package");
                app.Packages.Add(new PackageRequirement
                {
                    Family = ReadString(package, "family"),
                    MinimumVersion = ReadVersion(package, "minimumVersion"),
                });
            }
            return new PrerequisiteConfiguration
            {
                VisualCpp = visualCpp,
                DotNet = dotNet,
                WindowsAppRuntime = app,
            };
        }

        private static RuntimeRequirement ReadRuntime(IDictionary<string, object> root, string name)
        {
            IDictionary<string, object> value = RequireObject(RequireProperty(root, name), name);
            return new RuntimeRequirement
            {
                MinimumVersion = ReadVersion(value, "minimumVersion"),
                DownloadUri = ReadUri(value, "url"),
            };
        }

        private static object RequireProperty(IDictionary<string, object> value, string name)
        {
            object result;
            if (!value.TryGetValue(name, out result))
            {
                throw new FormatException("Missing prerequisite property: " + name);
            }
            return result;
        }

        private static IDictionary<string, object> RequireObject(object value, string name)
        {
            IDictionary<string, object> result = value as IDictionary<string, object>;
            if (result == null)
            {
                throw new FormatException(name + " must be a JSON object.");
            }
            return result;
        }

        private static IList<object> RequireArray(object value, string name)
        {
            IList<object> result = value as IList<object>;
            if (result == null)
            {
                throw new FormatException(name + " must be a JSON array.");
            }
            return result;
        }

        private static string ReadString(IDictionary<string, object> value, string name)
        {
            string result = RequireProperty(value, name) as string;
            if (string.IsNullOrWhiteSpace(result))
            {
                throw new FormatException(name + " must be a non-empty string.");
            }
            return result;
        }

        private static Version ReadVersion(IDictionary<string, object> value, string name)
        {
            Version result;
            if (!Version.TryParse(ReadString(value, name), out result))
            {
                throw new FormatException(name + " is not a valid version.");
            }
            return result;
        }

        private static Uri ReadUri(IDictionary<string, object> value, string name)
        {
            Uri result;
            if (!Uri.TryCreate(ReadString(value, name), UriKind.Absolute, out result))
            {
                throw new FormatException(name + " is not an absolute URI.");
            }
            MicrosoftDownload.ValidateUri(result);
            return result;
        }
    }

    internal class RuntimeRequirement
    {
        internal Version MinimumVersion;
        internal Uri DownloadUri;
    }

    internal sealed class WindowsAppRuntimeRequirement : RuntimeRequirement
    {
        internal List<PackageRequirement> Packages;
    }

    internal sealed class PackageRequirement
    {
        internal string Family;
        internal Version MinimumVersion;
    }

    internal static class VersionChecks
    {
        internal static bool HasDotNetVersion(IEnumerable<string> versions, Version minimumVersion)
        {
            foreach (string candidate in versions)
            {
                Version parsed;
                if (Version.TryParse(candidate, out parsed)
                    && parsed.Major == minimumVersion.Major
                    && parsed.Minor == minimumVersion.Minor
                    && parsed >= minimumVersion)
                {
                    return true;
                }
            }
            return false;
        }

        internal static bool HasVisualCppVersion(string candidate, Version minimumVersion)
        {
            Version parsed;
            return !string.IsNullOrWhiteSpace(candidate)
                && Version.TryParse(candidate.Trim().TrimStart('v'), out parsed)
                && parsed.Major == 14
                && parsed >= minimumVersion;
        }
    }

    internal static class PlatformSupport
    {
        private const uint MinimumWindowsBuild = 17763;

        internal static bool IsSupportedVersion(uint majorVersion, uint buildNumber)
        {
            return majorVersion > 10
                || (majorVersion == 10 && buildNumber >= MinimumWindowsBuild);
        }

        internal static void AssertSupported()
        {
            if (!Environment.Is64BitOperatingSystem || !Environment.Is64BitProcess)
            {
                throw Unsupported(
                    "SIDEY Setup requires 64-bit Windows and a 64-bit prerequisite helper.",
                    "Environment.Is64BitOperatingSystem; Environment.Is64BitProcess");
            }

            OsVersionInfo version;
            if (!TryGetActualVersion(out version))
            {
                throw Unsupported(
                    "The Windows version could not be determined safely.",
                    "RtlGetVersion");
            }
            if (!IsSupportedVersion(version.MajorVersion, version.BuildNumber))
            {
                throw Unsupported(
                    "SIDEY requires Windows 10 version 1809 (build 17763) or later.",
                    "Windows build >= 17763");
            }
        }

        internal static string GetActualVersionString()
        {
            OsVersionInfo version;
            if (!TryGetActualVersion(out version))
            {
                return "UNKNOWN";
            }
            return string.Format(
                CultureInfo.InvariantCulture,
                "Microsoft Windows NT {0}.{1}.{2}.0",
                version.MajorVersion,
                version.MinorVersion,
                version.BuildNumber);
        }

        private static bool TryGetActualVersion(out OsVersionInfo version)
        {
            version = new OsVersionInfo
            {
                Size = (uint)Marshal.SizeOf(typeof(OsVersionInfo)),
            };
            return RtlGetVersion(ref version) == 0;
        }

        private static InstallerFailureException Unsupported(string message, string command)
        {
            return new InstallerFailureException(
                message,
                null,
                "1633",
                "HELPER",
                "CHECK",
                "INCOMPATIBLE_SYSTEM",
                "Windows 10 1809 x64",
                command,
                null,
                null);
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct OsVersionInfo
        {
            internal uint Size;
            internal uint MajorVersion;
            internal uint MinorVersion;
            internal uint BuildNumber;
            internal uint PlatformId;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] internal string ServicePack;
        }

        [DllImport("ntdll.dll")]
        private static extern int RtlGetVersion(ref OsVersionInfo versionInformation);
    }

    internal static class PrerequisiteInstallPolicy
    {
        internal static bool IsAvailableAfterNonzeroExit(
            int exitCode,
            Func<bool> availabilityCheck)
        {
            if (exitCode == 0)
            {
                throw new ArgumentOutOfRangeException("exitCode");
            }
            if (availabilityCheck == null)
            {
                throw new ArgumentNullException("availabilityCheck");
            }
            return availabilityCheck();
        }

        internal static bool IsAvailableAfterSuccessfulExit(Func<bool> availabilityCheck)
        {
            if (availabilityCheck == null)
            {
                throw new ArgumentNullException("availabilityCheck");
            }
            return availabilityCheck();
        }

    }

    internal static class PrerequisiteService
    {
        private sealed class Requirement
        {
            internal string Name;
            internal RuntimeRequirement Configuration;
            internal string Source;
            internal string FileName;
            internal string Arguments;
            internal Func<bool> IsAvailable;
            internal bool RunAsDesktopUser;
        }

        internal static int Ensure(
            PrerequisiteConfiguration configuration,
            string downloadDirectory,
            bool checkOnly,
            string desktopUserRunner,
            Action<string> warningWriter)
        {
            string fullDownloadDirectory;
            try
            {
                fullDownloadDirectory = Path.GetFullPath(downloadDirectory);
            }
            catch (Exception exception)
            {
                throw Failure(
                    "Prerequisite download directory validation failed.",
                    exception,
                    null,
                    "FILESYSTEM",
                    "DOWNLOAD",
                    null,
                    "Prerequisite download directory",
                    "Validate prerequisite download directory",
                    null);
            }

            string desktopUserSid;
            try
            {
                desktopUserSid = DesktopUserIdentity.GetSecurityIdentifier();
            }
            catch (Exception exception)
            {
                throw Failure(
                    "Windows App Runtime desktop-user identification failed.",
                    exception,
                    null,
                    "APPX",
                    "CHECK",
                    null,
                    "Windows App Runtime x64",
                    "Identify the interactive desktop user",
                    null);
            }
            Requirement[] requirements =
            {
                new Requirement
                {
                    Name = "Visual C++ v14 x64 Redistributable",
                    Configuration = configuration.VisualCpp,
                    Source = "VC_REDIST",
                    FileName = "vc_redist.x64.exe",
                    Arguments = "/install /quiet /norestart",
                    IsAvailable = delegate { return IsVisualCppAvailable(configuration.VisualCpp); },
                },
                new Requirement
                {
                    Name = ".NET 10 x64 Runtime",
                    Configuration = configuration.DotNet,
                    Source = "DOTNET",
                    FileName = "dotnet-runtime-x64.exe",
                    Arguments = "/install /quiet /norestart",
                    IsAvailable = delegate { return IsDotNetAvailable(configuration.DotNet); },
                },
                new Requirement
                {
                    Name = "Windows App Runtime x64",
                    Configuration = configuration.WindowsAppRuntime,
                    Source = "APPX",
                    FileName = "windowsappruntimeinstall-x64.exe",
                    Arguments = "--quiet",
                    IsAvailable = delegate
                    {
                        return IsWindowsAppRuntimeAvailable(
                            configuration.WindowsAppRuntime,
                            desktopUserSid);
                    },
                    RunAsDesktopUser = true,
                },
            };

            foreach (Requirement requirement in requirements)
            {
                bool available;
                try
                {
                    available = requirement.IsAvailable();
                }
                catch (Exception exception)
                {
                    throw Failure(
                        requirement.Name + " availability check failed.",
                        exception,
                        null,
                        requirement.Source,
                        "CHECK",
                        null,
                        requirement.Name,
                        "Check prerequisite availability",
                        null);
                }

                if (available)
                {
                    continue;
                }
                if (checkOnly)
                {
                    throw Failure(
                        requirement.Name + ": missing",
                        null,
                        "0x80073CFD",
                        requirement.Source,
                        "CHECK",
                        "DEPENDENCY_MISSING",
                        requirement.Name,
                        "Check prerequisite availability",
                        null);
                }

                bool useDesktopUserRunner = requirement.RunAsDesktopUser;
                string requirementDownloadDirectory;
                string downloadPath;
                try
                {
                    if (useDesktopUserRunner)
                    {
                        requirementDownloadDirectory =
                            PrepareDesktopUserDownloadDirectory(desktopUserSid);
                    }
                    else
                    {
                        requirementDownloadDirectory = fullDownloadDirectory;
                        PrepareDownloadDirectory(requirementDownloadDirectory);
                    }

                    downloadPath = SafeDownloadPath(
                        requirementDownloadDirectory,
                        requirement.FileName);
                }
                catch (Exception exception)
                {
                    throw Failure(
                        requirement.Name + " download preparation failed.",
                        exception,
                        null,
                        "FILESYSTEM",
                        "DOWNLOAD",
                        null,
                        requirement.Name,
                        "Prepare secure prerequisite download path",
                        null);
                }
                try
                {
                    int code;
                    FileStream downloadFile = null;
                    FileStream verifiedFileLock = null;
                    try
                    {
                        // CreateNew prevents an untrusted pre-existing file from being used.
                        // A writable handle cannot remain open while Windows maps an EXE.
                        // Bridge to a read-only, no-write/no-delete-share handle without ever
                        // leaving the path unowned, then verify under that final lock.
                        downloadFile = new FileStream(
                            downloadPath,
                            FileMode.CreateNew,
                            FileAccess.ReadWrite,
                            FileShare.Read);
                        try
                        {
                            MicrosoftDownload.Save(
                                requirement.Configuration.DownloadUri,
                                downloadFile);
                        }
                        catch (Exception exception)
                        {
                            throw Failure(
                                requirement.Name + " download failed.",
                                exception,
                                null,
                                "NETWORK",
                                "DOWNLOAD",
                                InstallerErrors.DownloadCategory(exception),
                                requirement.Name,
                                "GET " + requirement.Configuration.DownloadUri.GetLeftPart(UriPartial.Path),
                                null);
                        }

                        byte[] downloadedHash = ComputeSha256(downloadFile);
                        verifiedFileLock = TransitionToExecutableReadLock(
                            downloadPath,
                            downloadFile);
                        downloadFile = null;

                        try
                        {
                            AssertSameSha256(verifiedFileLock, downloadedHash);
                            AuthenticodeVerifier.AssertMicrosoftSignature(downloadPath);
                        }
                        catch (Exception exception)
                        {
                            throw Failure(
                                requirement.Name + " signature verification failed.",
                                exception,
                                null,
                                "AUTHENTICODE",
                                "VERIFY",
                                "SIGNATURE_ERROR",
                                requirement.Name,
                                "WinVerifyTrust " + requirement.FileName,
                                null);
                        }

                        try
                        {
                            code = requirement.RunAsDesktopUser
                                ? RunInstallerAsDesktopUser(
                                    downloadPath,
                                    desktopUserRunner)
                                : RunInstaller(downloadPath, requirement.Arguments);
                        }
                        catch (Exception exception)
                        {
                            throw Failure(
                                requirement.Name + " installer could not be started.",
                                exception,
                                null,
                                requirement.Source,
                                "INSTALL",
                                null,
                                requirement.Name,
                                requirement.FileName + " " + requirement.Arguments,
                                null);
                        }
                    }
                    finally
                    {
                        if (verifiedFileLock != null)
                        {
                            verifiedFileLock.Dispose();
                        }
                        if (downloadFile != null)
                        {
                            downloadFile.Dispose();
                        }
                    }

                    if (code == 3010 || code == 1641)
                    {
                        return code;
                    }
                    if (code != 0)
                    {
                        bool availableAfterFailure;
                        try
                        {
                            availableAfterFailure =
                                PrerequisiteInstallPolicy.IsAvailableAfterNonzeroExit(
                                    code,
                                    requirement.IsAvailable);
                        }
                        catch (Exception exception)
                        {
                            throw Failure(
                                requirement.Name + " availability check failed after installer exit "
                                    + code.ToString(CultureInfo.InvariantCulture) + ".",
                                exception,
                                null,
                                requirement.Source,
                                "VERIFY",
                                null,
                                requirement.Name,
                                "Check prerequisite availability",
                                code.ToString(CultureInfo.InvariantCulture));
                        }
                        if (!availableAfterFailure)
                        {
                            throw Failure(
                                requirement.Name + " installation failed (exit=" + code.ToString(CultureInfo.InvariantCulture) + ").",
                                null,
                                code,
                                requirement.Source,
                                "INSTALL",
                                null,
                                requirement.Name,
                                requirement.FileName + " " + requirement.Arguments,
                                code.ToString(CultureInfo.InvariantCulture));
                        }
                        continue;
                    }
                    bool availableAfterInstall;
                    try
                    {
                        availableAfterInstall =
                            PrerequisiteInstallPolicy.IsAvailableAfterSuccessfulExit(
                                requirement.IsAvailable);
                    }
                    catch (Exception exception)
                    {
                        throw Failure(
                            requirement.Name + " availability check failed after successful installer exit.",
                            exception,
                            null,
                            requirement.Source,
                            "VERIFY",
                            null,
                            requirement.Name,
                            "Check prerequisite availability",
                            "0");
                    }
                    if (!availableAfterInstall)
                    {
                        throw Failure(
                            requirement.Name + " is still unavailable after installation.",
                            null,
                            "0x80073CFD",
                            requirement.Source,
                            "VERIFY",
                            "DEPENDENCY_MISSING",
                            requirement.Name,
                            "Check prerequisite availability",
                            null);
                    }
                }
                finally
                {
                    TryDeleteDownloadFile(
                        downloadPath,
                        requirement.Name,
                        warningWriter);
                }
            }

            return 0;
        }

        private static InstallerFailureException Failure(
            string message,
            Exception innerException,
            object nativeCode,
            string source,
            string stage,
            string categoryHint,
            string target,
            string commandDescription,
            string exitCode)
        {
            return new InstallerFailureException(
                message,
                innerException,
                nativeCode,
                source,
                stage,
                categoryHint,
                target,
                commandDescription,
                exitCode,
                null);
        }

        private static string SafeDownloadPath(string directory, string fileName)
        {
            string path = Path.GetFullPath(Path.Combine(directory, fileName));
            string parent = Path.GetDirectoryName(path);
            string fullDirectory = Path.GetFullPath(directory)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (!string.Equals(parent, fullDirectory, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Unsafe prerequisite download path.");
            }
            DeleteStaleDownloadFile(path);
            return path;
        }

        private static string GetDesktopUserDownloadDirectory()
        {
            return Path.GetFullPath(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "SIDEY-PrerequisiteDownloads"));
        }

        private static string PrepareDesktopUserDownloadDirectory(
            string userSecurityIdentifier)
        {
            string programData = Path.GetFullPath(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData));
            PrepareDownloadDirectory(programData);

            string expected = GetDesktopUserDownloadDirectory();
            AssertNoReparseAncestors(expected);
            SecureDesktopUserDirectory(expected, userSecurityIdentifier);
            AssertNoReparseAncestors(expected);
            return expected;
        }

        private static FileStream TransitionToExecutableReadLock(
            string path,
            FileStream downloadFile)
        {
            if (downloadFile == null)
            {
                throw new ArgumentNullException("downloadFile");
            }

            FileStream transitionFile = null;
            try
            {
                transitionFile = new FileStream(
                    path,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite);
                downloadFile.Dispose();
                downloadFile = null;
                return new FileStream(
                    path,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.Read);
            }
            finally
            {
                if (transitionFile != null)
                {
                    transitionFile.Dispose();
                }
                if (downloadFile != null)
                {
                    downloadFile.Dispose();
                }
            }
        }

        private static byte[] ComputeSha256(Stream stream)
        {
            if (stream == null || !stream.CanRead || !stream.CanSeek)
            {
                throw new ArgumentException(
                    "The prerequisite stream must be readable and seekable.",
                    "stream");
            }

            long originalPosition = stream.Position;
            try
            {
                stream.Position = 0;
                using (SHA256 algorithm = SHA256.Create())
                {
                    return algorithm.ComputeHash(stream);
                }
            }
            finally
            {
                stream.Position = originalPosition;
            }
        }

        private static void AssertSameSha256(Stream stream, byte[] expectedHash)
        {
            byte[] actualHash = ComputeSha256(stream);
            if (expectedHash == null || expectedHash.Length != actualHash.Length)
            {
                throw new CryptographicException(
                    "The prerequisite download changed before signature verification.");
            }

            int difference = 0;
            for (int index = 0; index < expectedHash.Length; index++)
            {
                difference |= expectedHash[index] ^ actualHash[index];
            }
            if (difference != 0)
            {
                throw new CryptographicException(
                    "The prerequisite download changed before signature verification.");
            }
        }

        private static void PrepareDownloadDirectory(string directory)
        {
            string fullDirectory = Path.GetFullPath(directory);
            AssertNoReparseAncestors(fullDirectory);
            Directory.CreateDirectory(fullDirectory);
            AssertNoReparseAncestors(fullDirectory);

            FileAttributes attributes = File.GetAttributes(fullDirectory);
            if ((attributes & FileAttributes.Directory) == 0
                || (attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException(
                    "The prerequisite download directory must be an ordinary directory.");
            }
        }

        private static void AssertNoReparseAncestors(string path)
        {
            for (DirectoryInfo current = new DirectoryInfo(path);
                current != null;
                current = current.Parent)
            {
                if (current.Exists
                    && (current.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new IOException(
                        "The prerequisite download path cannot contain a reparse point.");
                }
            }
        }

        private static void DeleteStaleDownloadFile(string path)
        {
            if (Directory.Exists(path))
            {
                throw new IOException(
                    "The prerequisite download destination cannot be a directory.");
            }
            if (!File.Exists(path))
            {
                return;
            }

            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReparsePoint) != 0
                || (attributes & FileAttributes.Directory) != 0)
            {
                throw new IOException(
                    "The prerequisite download destination cannot be a reparse point.");
            }

            // An active installer keeps this file open without delete/write sharing.
            // Taking an exclusive handle makes stale cleanup fail closed instead of
            // deleting a download that another Setup instance is still using.
            using (new FileStream(
                path,
                FileMode.Open,
                FileAccess.ReadWrite,
                FileShare.None))
            {
            }
            File.Delete(path);
            if (File.Exists(path) || Directory.Exists(path))
            {
                throw new IOException("The stale prerequisite download could not be removed.");
            }
        }

        private static void TryDeleteDownloadFile(
            string path,
            string component,
            Action<string> warningWriter)
        {
            try
            {
                DeleteStaleDownloadFile(path);
            }
            catch (Exception cleanupException)
            {
                if (warningWriter == null)
                {
                    return;
                }
                try
                {
                    warningWriter(
                        "Prerequisite download cleanup failed; component="
                        + component
                        + "; nativeCode="
                        + InstallerErrors.NormalizeNativeCode(cleanupException.HResult)
                        + "; detail="
                        + cleanupException.Message);
                }
                catch
                {
                    // Cleanup diagnostics never replace the install result.
                }
            }
        }

        private static void SecureDesktopUserDirectory(
            string directory,
            string userSecurityIdentifier)
        {
            var administrators = new SecurityIdentifier("S-1-5-32-544");
            var system = new SecurityIdentifier("S-1-5-18");
            var desktopUser = new SecurityIdentifier(userSecurityIdentifier);
            const InheritanceFlags inheritance =
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.SetOwner(administrators);
            security.AddAccessRule(new FileSystemAccessRule(
                administrators,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                system,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                desktopUser,
                FileSystemRights.ReadAndExecute | FileSystemRights.Synchronize,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            bool existed = Directory.Exists(directory);
            DirectoryInfo information;
            if (existed)
            {
                information = new DirectoryInfo(directory);
                AssertDirectoryIsNotUserControlled(information, administrators, system);
                information.SetAccessControl(security);
            }
            else
            {
                information = Directory.CreateDirectory(directory, security);
            }
            information.Refresh();
            if (!information.Exists
                || (information.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException(
                    "The prerequisite download directory changed while access was secured.");
            }
            AssertDirectoryIsNotUserControlled(information, administrators, system);
        }

        private static void AssertDirectoryIsNotUserControlled(
            DirectoryInfo information,
            SecurityIdentifier administrators,
            SecurityIdentifier system)
        {
            DirectorySecurity security = information.GetAccessControl(
                AccessControlSections.Access | AccessControlSections.Owner);
            var owner = (SecurityIdentifier)security.GetOwner(typeof(SecurityIdentifier));
            if ((!owner.Equals(administrators) && !owner.Equals(system))
                || !security.AreAccessRulesProtected)
            {
                throw new UnauthorizedAccessException(
                    "The prerequisite download directory is not owned by a trusted principal.");
            }

            int safeUntrustedRights = (int)(
                FileSystemRights.ReadAndExecute
                | FileSystemRights.ReadPermissions
                | FileSystemRights.Synchronize);
            AuthorizationRuleCollection rules = security.GetAccessRules(
                true,
                true,
                typeof(SecurityIdentifier));
            foreach (FileSystemAccessRule rule in rules)
            {
                var identity = (SecurityIdentifier)rule.IdentityReference;
                if (rule.AccessControlType == AccessControlType.Allow
                    && !identity.Equals(administrators)
                    && !identity.Equals(system)
                    && (((int)rule.FileSystemRights) & ~safeUntrustedRights) != 0)
                {
                    throw new UnauthorizedAccessException(
                        "The prerequisite download directory grants unsafe write access.");
                }
            }
        }

        private static bool IsVisualCppAvailable(RuntimeRequirement requirement)
        {
            using (RegistryKey machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32))
            using (RegistryKey key = machine.OpenSubKey(@"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"))
            {
                if (key == null || Convert.ToInt32(key.GetValue("Installed", 0), CultureInfo.InvariantCulture) != 1)
                {
                    return false;
                }
                return VersionChecks.HasVisualCppVersion(
                    Convert.ToString(key.GetValue("Version"), CultureInfo.InvariantCulture),
                    requirement.MinimumVersion);
            }
        }

        private static bool IsDotNetAvailable(RuntimeRequirement requirement)
        {
            string installLocation;
            using (RegistryKey machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32))
            using (RegistryKey key = machine.OpenSubKey(@"SOFTWARE\dotnet\Setup\InstalledVersions\x64"))
            {
                if (key == null)
                {
                    return false;
                }
                installLocation = Convert.ToString(key.GetValue("InstallLocation"), CultureInfo.InvariantCulture);
            }
            if (string.IsNullOrWhiteSpace(installLocation))
            {
                return false;
            }
            string hostPath = Path.Combine(installLocation, "dotnet.exe");
            if (!File.Exists(hostPath))
            {
                return false;
            }

            var versions = new List<string>();
            var error = new StringBuilder();
            var startInfo = new ProcessStartInfo
            {
                FileName = hostPath,
                Arguments = "--list-runtimes",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using (Process process = new Process { StartInfo = startInfo })
            {
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (eventArgs.Data == null)
                    {
                        return;
                    }
                    Match match = Regex.Match(
                        eventArgs.Data,
                        @"^Microsoft\.NETCore\.App (\d+\.\d+\.\d+) \[");
                    if (match.Success)
                    {
                        lock (versions)
                        {
                            versions.Add(match.Groups[1].Value);
                        }
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (eventArgs.Data != null)
                    {
                        lock (error)
                        {
                            if (error.Length < 1000)
                            {
                                error.AppendLine(eventArgs.Data);
                            }
                        }
                    }
                };
                if (!process.Start())
                {
                    return false;
                }
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                if (!process.WaitForExit(30000))
                {
                    try { process.Kill(); } catch { }
                    return false;
                }
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    return false;
                }
            }
            return VersionChecks.HasDotNetVersion(versions, requirement.MinimumVersion);
        }

        private static bool IsWindowsAppRuntimeAvailable(
            WindowsAppRuntimeRequirement requirement,
            string userSecurityIdentifier)
        {
            foreach (PackageRequirement package in requirement.Packages)
            {
                if (!WindowsPackageQuery.HasPackage(
                    package.Family,
                    package.MinimumVersion,
                    userSecurityIdentifier))
                {
                    return false;
                }
            }
            return true;
        }

        private static int RunInstallerAsDesktopUser(
            string path,
            string desktopUserRunner)
        {
            if (string.IsNullOrWhiteSpace(desktopUserRunner))
            {
                throw new UnauthorizedAccessException(
                    "A desktop-user process runner is required for Windows App Runtime installation.");
            }

            string runnerPath = Path.GetFullPath(desktopUserRunner);
            if (!File.Exists(runnerPath)
                || !string.Equals(
                    Path.GetFileName(runnerPath),
                    "Sidey.SetupSupport.exe",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new FileNotFoundException(
                    "The SIDEY desktop-user process runner is unavailable.",
                    runnerPath);
            }
            return RunInstaller(
                runnerPath,
                "--run-windows-app-runtime-as-desktop-user " + QuoteArgument(path));
        }

        private static string QuoteArgument(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static int RunInstaller(string path, string arguments)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = path,
                Arguments = arguments,
                WorkingDirectory = Path.GetDirectoryName(path),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            };
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("Prerequisite installer did not start.");
                }
                process.WaitForExit();
                return process.ExitCode;
            }
        }
    }

    internal static class MicrosoftDownload
    {
        private static readonly HashSet<string> AllowedHosts = new HashSet<string>(
            new[]
            {
                "aka.ms",
                "builds.dotnet.microsoft.com",
                "download.visualstudio.microsoft.com",
                "download.microsoft.com",
            },
            StringComparer.OrdinalIgnoreCase);

        internal static void ValidateUri(Uri uri)
        {
            if (uri == null
                || !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.Ordinal)
                || uri.Port != 443
                || !string.IsNullOrEmpty(uri.UserInfo)
                || !AllowedHosts.Contains(uri.DnsSafeHost))
            {
                throw new InvalidOperationException("Unexpected Microsoft download URL.");
            }
        }

        internal static void Save(Uri uri, Stream destination)
        {
            if (destination == null
                || !destination.CanWrite
                || !destination.CanSeek)
            {
                throw new ArgumentException(
                    "The runtime download destination must be a writable seekable stream.",
                    "destination");
            }
            destination.SetLength(0);
            destination.Position = 0;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            Uri current = uri;
            for (int redirect = 0; redirect < 10; redirect++)
            {
                ValidateUri(current);
                var request = (HttpWebRequest)WebRequest.Create(current);
                request.AllowAutoRedirect = false;
                request.Timeout = 120000;
                request.ReadWriteTimeout = 120000;
                request.UserAgent = "SIDEY Setup prerequisite installer";
                using (var response = (HttpWebResponse)request.GetResponse())
                {
                    int status = (int)response.StatusCode;
                    if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308)
                    {
                        string location = response.Headers[HttpResponseHeader.Location];
                        if (string.IsNullOrWhiteSpace(location))
                        {
                            throw new WebException("Microsoft download redirect did not include a location.");
                        }
                        current = new Uri(current, location);
                        continue;
                    }
                    if (status != 200)
                    {
                        throw new WebException("Runtime download failed with HTTP status " + status + ".");
                    }
                    using (Stream input = response.GetResponseStream())
                    {
                        if (input == null)
                        {
                            throw new WebException("Runtime download returned no content.");
                        }
                        input.CopyTo(destination);
                        var fileDestination = destination as FileStream;
                        if (fileDestination != null)
                        {
                            fileDestination.Flush(true);
                        }
                        else
                        {
                            destination.Flush();
                        }
                        destination.Position = 0;
                    }
                    return;
                }
            }
            throw new WebException("Too many Microsoft download redirects.");
        }
    }

    internal static class AuthenticodeVerifier
    {
        private static readonly Guid GenericVerifyAction =
            new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        internal static bool IsMicrosoftCorporationSubject(string subject)
        {
            return !string.IsNullOrWhiteSpace(subject)
                && Regex.IsMatch(
                    subject,
                    "(^|,\\s*)O=Microsoft Corporation(,|$)",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        internal static void AssertMicrosoftSignature(string path)
        {
            int trustResult = VerifyEmbeddedSignature(path);
            if (trustResult != 0)
            {
                throw new Win32Exception(
                    trustResult,
                    "Runtime installer does not have a valid Authenticode signature.");
            }
            X509Certificate certificate = null;
            X509Certificate2 signer = null;
            try
            {
                certificate = X509Certificate.CreateFromSignedFile(path);
                signer = new X509Certificate2(certificate);
                if (!IsMicrosoftCorporationSubject(signer.Subject))
                {
                    throw new InvalidOperationException(
                        "Runtime installer signer is not Microsoft Corporation.");
                }
            }
            finally
            {
                if (signer != null) signer.Dispose();
                if (certificate != null) certificate.Dispose();
            }
        }

        private static int VerifyEmbeddedSignature(string path)
        {
            var fileInfo = new WinTrustFileInfo
            {
                StructureSize = (uint)Marshal.SizeOf(typeof(WinTrustFileInfo)),
                FilePath = path,
            };
            IntPtr fileInfoPointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WinTrustFileInfo)));
            try
            {
                Marshal.StructureToPtr(fileInfo, fileInfoPointer, false);
                var trustData = new WinTrustData
                {
                    StructureSize = (uint)Marshal.SizeOf(typeof(WinTrustData)),
                    UiChoice = 2,
                    RevocationChecks = 1,
                    UnionChoice = 1,
                    FileInfo = fileInfoPointer,
                    StateAction = 1,
                    ProviderFlags = 0x00000080,
                    UiContext = 0,
                };
                int result = WinVerifyTrust(IntPtr.Zero, GenericVerifyAction, ref trustData);
                trustData.StateAction = 2;
                WinVerifyTrust(IntPtr.Zero, GenericVerifyAction, ref trustData);
                return result;
            }
            finally
            {
                Marshal.DestroyStructure(fileInfoPointer, typeof(WinTrustFileInfo));
                Marshal.FreeHGlobal(fileInfoPointer);
            }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WinTrustFileInfo
        {
            internal uint StructureSize;
            [MarshalAs(UnmanagedType.LPWStr)] internal string FilePath;
            internal IntPtr FileHandle;
            internal IntPtr KnownSubject;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WinTrustData
        {
            internal uint StructureSize;
            internal IntPtr PolicyCallbackData;
            internal IntPtr SipClientData;
            internal uint UiChoice;
            internal uint RevocationChecks;
            internal uint UnionChoice;
            internal IntPtr FileInfo;
            internal uint StateAction;
            internal IntPtr StateData;
            [MarshalAs(UnmanagedType.LPWStr)] internal string UrlReference;
            internal uint ProviderFlags;
            internal uint UiContext;
        }

        [DllImport("wintrust.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int WinVerifyTrust(
            IntPtr window,
            [MarshalAs(UnmanagedType.LPStruct)] Guid action,
            ref WinTrustData trustData);
    }

    internal static class DesktopUserIdentity
    {
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const uint TokenQuery = 0x0008;

        internal static string GetSecurityIdentifier()
        {
            IntPtr shellWindow = GetShellWindow();
            uint shellProcessId;
            if (shellWindow == IntPtr.Zero
                || GetWindowThreadProcessId(shellWindow, out shellProcessId) == 0
                || shellProcessId == 0)
            {
                throw new InvalidOperationException("The desktop user could not be identified.");
            }

            IntPtr shellProcess = IntPtr.Zero;
            IntPtr shellToken = IntPtr.Zero;
            try
            {
                shellProcess = OpenProcess(
                    ProcessQueryLimitedInformation,
                    false,
                    shellProcessId);
                if (shellProcess == IntPtr.Zero
                    || !OpenProcessToken(shellProcess, TokenQuery, out shellToken))
                {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "The desktop user token could not be opened.");
                }
                using (var identity = new WindowsIdentity(shellToken))
                {
                    if (identity.User == null)
                    {
                        throw new InvalidOperationException(
                            "The desktop user security identifier is unavailable.");
                    }
                    return identity.User.Value;
                }
            }
            finally
            {
                if (shellToken != IntPtr.Zero)
                {
                    CloseHandle(shellToken);
                }
                if (shellProcess != IntPtr.Zero)
                {
                    CloseHandle(shellProcess);
                }
            }
        }

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("user32.dll")]
        private static extern IntPtr GetShellWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(
            IntPtr window,
            out uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(
            uint desiredAccess,
            bool inheritHandle,
            uint processId);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(
            IntPtr process,
            uint desiredAccess,
            out IntPtr token);
    }

    internal static class WindowsPackageQuery
    {
        internal static bool HasPackage(
            string family,
            Version minimumVersion,
            string userSecurityIdentifier)
        {
            Type managerType = Type.GetType(
                "Windows.Management.Deployment.PackageManager, Windows, ContentType=WindowsRuntime",
                true);
            Type packageType = Type.GetType(
                "Windows.ApplicationModel.Package, Windows, ContentType=WindowsRuntime",
                true);
            Type identityType = Type.GetType(
                "Windows.ApplicationModel.PackageId, Windows, ContentType=WindowsRuntime",
                true);
            Type versionType = Type.GetType(
                "Windows.ApplicationModel.PackageVersion, Windows, ContentType=WindowsRuntime",
                true);
            Type storageFolderType = Type.GetType(
                "Windows.Storage.StorageFolder, Windows, ContentType=WindowsRuntime",
                true);
            Type statusType = Type.GetType(
                "Windows.ApplicationModel.PackageStatus, Windows, ContentType=WindowsRuntime",
                true);
            MethodInfo findPackages = null;
            foreach (MethodInfo method in managerType.GetMethods())
            {
                ParameterInfo[] parameters = method.GetParameters();
                if (method.Name == "FindPackagesForUserWithPackageTypes"
                    && parameters.Length == 3
                    && parameters[0].ParameterType == typeof(string)
                    && parameters[1].ParameterType == typeof(string)
                    && parameters[2].ParameterType.IsEnum)
                {
                    findPackages = method;
                    break;
                }
            }
            if (findPackages == null)
            {
                throw new MissingMethodException("Windows package type query API is unavailable.");
            }

            object manager = Activator.CreateInstance(managerType);
            object packageTypes = Enum.ToObject(
                findPackages.GetParameters()[2].ParameterType,
                1 | 2); // PackageTypes.Main | PackageTypes.Framework
            var packages = findPackages.Invoke(
                manager,
                new object[] { userSecurityIdentifier, family, packageTypes }) as IEnumerable;
            if (packages == null)
            {
                throw new InvalidOperationException("Windows package query returned no enumerable result.");
            }

            PropertyInfo idProperty = packageType.GetProperty("Id");
            PropertyInfo installedLocationProperty = packageType.GetProperty("InstalledLocation");
            PropertyInfo statusProperty = packageType.GetProperty("Status");
            PropertyInfo familyNameProperty = identityType.GetProperty("FamilyName");
            PropertyInfo architectureProperty = identityType.GetProperty("Architecture");
            PropertyInfo versionProperty = identityType.GetProperty("Version");
            PropertyInfo pathProperty = storageFolderType.GetProperty("Path");
            MethodInfo verifyIsOk = statusType.GetMethod(
                "VerifyIsOK",
                BindingFlags.Public | BindingFlags.Instance,
                null,
                Type.EmptyTypes,
                null);
            if (idProperty == null || installedLocationProperty == null
                || statusProperty == null || familyNameProperty == null
                || architectureProperty == null || versionProperty == null
                || pathProperty == null || verifyIsOk == null)
            {
                throw new MissingMemberException("Windows package identity API is unavailable.");
            }

            foreach (object package in packages)
            {
                try
                {
                    object identity = idProperty.GetValue(package, null);
                    string packageFamily = (string)familyNameProperty.GetValue(identity, null);
                    object architecture = architectureProperty.GetValue(identity, null);
                    object packageVersion = versionProperty.GetValue(identity, null);
                    object installedLocation = installedLocationProperty.GetValue(package, null);
                    object status = statusProperty.GetValue(package, null);
                    string installedPath = installedLocation == null
                        ? null
                        : (string)pathProperty.GetValue(installedLocation, null);
                    if (string.Equals(packageFamily, family, StringComparison.Ordinal)
                        && string.Equals(architecture.ToString(), "X64", StringComparison.OrdinalIgnoreCase)
                        && ReadVersion(versionType, packageVersion) >= minimumVersion
                        && !string.IsNullOrWhiteSpace(installedPath)
                        && Directory.Exists(installedPath)
                        && status != null
                        && (bool)verifyIsOk.Invoke(status, null))
                    {
                        return true;
                    }
                }
                catch (Exception exception)
                {
                    if (exception is OutOfMemoryException || exception is StackOverflowException)
                    {
                        throw;
                    }
                }
            }
            return false;
        }

        private static Version ReadVersion(Type versionType, object value)
        {
            return new Version(
                ReadVersionPart(versionType, value, "Major"),
                ReadVersionPart(versionType, value, "Minor"),
                ReadVersionPart(versionType, value, "Build"),
                ReadVersionPart(versionType, value, "Revision"));
        }

        private static int ReadVersionPart(Type versionType, object value, string name)
        {
            FieldInfo field = versionType.GetField(name);
            if (field == null)
            {
                throw new MissingMemberException("Windows package version API is unavailable.");
            }
            return Convert.ToInt32(field.GetValue(value), CultureInfo.InvariantCulture);
        }
    }

    internal static class WindowsPackageStatus
    {
        internal static bool IsUsable(string packageFullName)
        {
            Type managerType = Type.GetType(
                "Windows.Management.Deployment.PackageManager, Windows, ContentType=WindowsRuntime",
                true);
            Type packageType = Type.GetType(
                "Windows.ApplicationModel.Package, Windows, ContentType=WindowsRuntime",
                true);
            Type statusType = Type.GetType(
                "Windows.ApplicationModel.PackageStatus, Windows, ContentType=WindowsRuntime",
                true);
            MethodInfo findPackage = null;
            foreach (MethodInfo method in managerType.GetMethods())
            {
                if (method.Name == "FindPackageForUser"
                    && method.GetParameters().Length == 2
                    && method.GetParameters()[0].ParameterType == typeof(string)
                    && method.GetParameters()[1].ParameterType == typeof(string))
                {
                    findPackage = method;
                    break;
                }
            }
            MethodInfo verifyIsOk = statusType.GetMethod(
                "VerifyIsOK",
                BindingFlags.Public | BindingFlags.Instance,
                null,
                Type.EmptyTypes,
                null);
            PropertyInfo statusProperty = packageType.GetProperty("Status");
            if (findPackage == null || statusProperty == null || verifyIsOk == null)
            {
                throw new MissingMethodException("Windows package status API is unavailable.");
            }

            object manager = Activator.CreateInstance(managerType);
            object package = findPackage.Invoke(manager, new object[] { string.Empty, packageFullName });
            if (package == null)
            {
                return false;
            }
            object status = statusProperty.GetValue(package, null);
            if (status == null)
            {
                return false;
            }
            return (bool)verifyIsOk.Invoke(status, null);
        }
    }

    internal static class PrivateRuntimeCleanup
    {
        internal static void Remove(string installDirectory)
        {
            string installRoot = Path.GetFullPath(installDirectory)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string driveRoot = Path.GetPathRoot(installRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (string.Equals(installRoot, driveRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("The installation directory cannot be a drive root.");
            }

            Directory.SetCurrentDirectory(AppDomain.CurrentDomain.BaseDirectory);
            DirectoryInfo ancestor = new DirectoryInfo(installRoot);
            while (ancestor != null)
            {
                if (ancestor.Exists && IsReparsePoint(ancestor.Attributes))
                {
                    throw new InvalidOperationException("The installation path contains a reparse point.");
                }
                ancestor = ancestor.Parent;
            }

            string runtime = Path.Combine(installRoot, "Runtime");
            if (!Directory.Exists(runtime) && !File.Exists(runtime))
            {
                return;
            }
            FileAttributes rootAttributes = File.GetAttributes(runtime);
            if (IsReparsePoint(rootAttributes) || (rootAttributes & FileAttributes.Directory) == 0)
            {
                throw new InvalidOperationException("The private Runtime tree contains a reparse point.");
            }

            var pending = new Queue<string>();
            var directories = new List<string>();
            var files = new List<string>();
            pending.Enqueue(runtime);
            while (pending.Count > 0)
            {
                string directory = pending.Dequeue();
                FileAttributes attributes = File.GetAttributes(directory);
                if (IsReparsePoint(attributes))
                {
                    throw new InvalidOperationException("The private Runtime tree contains a reparse point.");
                }
                directories.Add(directory);
                foreach (string child in Directory.GetFileSystemEntries(directory))
                {
                    FileAttributes childAttributes = File.GetAttributes(child);
                    if (IsReparsePoint(childAttributes))
                    {
                        throw new InvalidOperationException("The private Runtime tree contains a reparse point.");
                    }
                    if ((childAttributes & FileAttributes.Directory) != 0)
                    {
                        pending.Enqueue(child);
                    }
                    else
                    {
                        files.Add(child);
                    }
                }
            }
            foreach (string file in files)
            {
                File.SetAttributes(file, FileAttributes.Normal);
                File.Delete(file);
            }
            for (int index = directories.Count - 1; index >= 0; index--)
            {
                File.SetAttributes(directories[index], FileAttributes.Directory);
                Directory.Delete(directories[index], false);
            }
        }

        private static bool IsReparsePoint(FileAttributes attributes)
        {
            return (attributes & FileAttributes.ReparsePoint) != 0;
        }
    }

    internal static class MiniJson
    {
        internal static object Parse(string text)
        {
            var parser = new Parser(text);
            object result = parser.ReadValue();
            parser.SkipWhiteSpace();
            if (!parser.AtEnd)
            {
                throw new FormatException("Unexpected trailing JSON content.");
            }
            return result;
        }

        private sealed class Parser
        {
            private readonly string text;
            private int index;

            internal Parser(string text)
            {
                this.text = text ?? throw new ArgumentNullException("text");
            }

            internal bool AtEnd { get { return index >= text.Length; } }

            internal void SkipWhiteSpace()
            {
                while (!AtEnd && char.IsWhiteSpace(text[index])) index++;
            }

            internal object ReadValue()
            {
                SkipWhiteSpace();
                if (AtEnd) throw new FormatException("Unexpected end of JSON.");
                switch (text[index])
                {
                    case '{': return ReadObject();
                    case '[': return ReadArray();
                    case '"': return ReadString();
                    case 't': ReadLiteral("true"); return true;
                    case 'f': ReadLiteral("false"); return false;
                    case 'n': ReadLiteral("null"); return null;
                    default: return ReadNumber();
                }
            }

            private IDictionary<string, object> ReadObject()
            {
                Expect('{');
                var result = new Dictionary<string, object>(StringComparer.Ordinal);
                SkipWhiteSpace();
                if (TryConsume('}')) return result;
                while (true)
                {
                    SkipWhiteSpace();
                    string name = ReadString();
                    SkipWhiteSpace();
                    Expect(':');
                    if (result.ContainsKey(name)) throw new FormatException("Duplicate JSON property: " + name);
                    result.Add(name, ReadValue());
                    SkipWhiteSpace();
                    if (TryConsume('}')) return result;
                    Expect(',');
                }
            }

            private IList<object> ReadArray()
            {
                Expect('[');
                var result = new List<object>();
                SkipWhiteSpace();
                if (TryConsume(']')) return result;
                while (true)
                {
                    result.Add(ReadValue());
                    SkipWhiteSpace();
                    if (TryConsume(']')) return result;
                    Expect(',');
                }
            }

            private string ReadString()
            {
                Expect('"');
                var result = new StringBuilder();
                while (!AtEnd)
                {
                    char character = text[index++];
                    if (character == '"') return result.ToString();
                    if (character < 0x20) throw new FormatException("Invalid JSON string character.");
                    if (character != '\\')
                    {
                        result.Append(character);
                        continue;
                    }
                    if (AtEnd) throw new FormatException("Unexpected end of JSON escape.");
                    char escape = text[index++];
                    switch (escape)
                    {
                        case '"': result.Append('"'); break;
                        case '\\': result.Append('\\'); break;
                        case '/': result.Append('/'); break;
                        case 'b': result.Append('\b'); break;
                        case 'f': result.Append('\f'); break;
                        case 'n': result.Append('\n'); break;
                        case 'r': result.Append('\r'); break;
                        case 't': result.Append('\t'); break;
                        case 'u': result.Append(ReadUnicodeEscape()); break;
                        default: throw new FormatException("Invalid JSON escape sequence.");
                    }
                }
                throw new FormatException("Unterminated JSON string.");
            }

            private char ReadUnicodeEscape()
            {
                if (index + 4 > text.Length) throw new FormatException("Incomplete JSON unicode escape.");
                int value;
                if (!int.TryParse(text.Substring(index, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value))
                {
                    throw new FormatException("Invalid JSON unicode escape.");
                }
                index += 4;
                return (char)value;
            }

            private object ReadNumber()
            {
                int start = index;
                if (!AtEnd && text[index] == '-') index++;
                while (!AtEnd && char.IsDigit(text[index])) index++;
                if (!AtEnd && text[index] == '.')
                {
                    index++;
                    while (!AtEnd && char.IsDigit(text[index])) index++;
                }
                if (!AtEnd && (text[index] == 'e' || text[index] == 'E'))
                {
                    index++;
                    if (!AtEnd && (text[index] == '+' || text[index] == '-')) index++;
                    while (!AtEnd && char.IsDigit(text[index])) index++;
                }
                if (index == start) throw new FormatException("Invalid JSON value.");
                double value;
                if (!double.TryParse(
                    text.Substring(start, index - start),
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out value))
                {
                    throw new FormatException("Invalid JSON number.");
                }
                return value;
            }

            private void ReadLiteral(string literal)
            {
                if (index + literal.Length > text.Length
                    || !string.Equals(text.Substring(index, literal.Length), literal, StringComparison.Ordinal))
                {
                    throw new FormatException("Invalid JSON literal.");
                }
                index += literal.Length;
            }

            private void Expect(char character)
            {
                SkipWhiteSpace();
                if (AtEnd || text[index] != character)
                {
                    throw new FormatException("Expected JSON character: " + character);
                }
                index++;
            }

            private bool TryConsume(char character)
            {
                if (!AtEnd && text[index] == character)
                {
                    index++;
                    return true;
                }
                return false;
            }
        }
    }
}
