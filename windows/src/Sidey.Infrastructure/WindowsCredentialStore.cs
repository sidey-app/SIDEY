using System.ComponentModel;
using System.Runtime.InteropServices;
using Sidey.Core.Abstractions;

namespace Sidey.Infrastructure;

public sealed class WindowsCredentialStore : ICredentialStore
{
    private const string Prefix = "SIDEY/";

    public ValueTask<string?> ReadAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
        ReadTargetAsync(Prefix + key, cancellationToken);

    public ValueTask WriteAsync(
        CredentialKey key,
        string value,
        CancellationToken cancellationToken = default) =>
        WriteTargetAsync(Prefix + key, value, cancellationToken);

    public ValueTask DeleteAsync(CredentialKey key, CancellationToken cancellationToken = default) =>
        DeleteTargetAsync(Prefix + key, cancellationToken);

    public ValueTask<string?> ReadInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default) =>
        ReadTargetAsync(InviteTarget(roomId), cancellationToken);

    public ValueTask WriteInviteCodeAsync(
        Guid roomId,
        string inviteCode,
        CancellationToken cancellationToken = default) =>
        WriteTargetAsync(InviteTarget(roomId), inviteCode, cancellationToken);

    public ValueTask DeleteInviteCodeAsync(
        Guid roomId,
        CancellationToken cancellationToken = default) =>
        DeleteTargetAsync(InviteTarget(roomId), cancellationToken);

    private static ValueTask<string?> ReadTargetAsync(string target, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        EnsureWindows();
        if (!NativeMethods.CredRead(target, CredentialType.Generic, 0, out var pointer))
        {
            var error = Marshal.GetLastPInvokeError();
            return error == NativeMethods.ErrorNotFound
                ? ValueTask.FromResult<string?>(null)
                : ValueTask.FromException<string?>(new Win32Exception(error, "Credential Manager read failed."));
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == nint.Zero || credential.CredentialBlobSize == 0)
            {
                return ValueTask.FromResult<string?>(string.Empty);
            }

            return ValueTask.FromResult<string?>(Marshal.PtrToStringUni(
                credential.CredentialBlob,
                checked((int)credential.CredentialBlobSize / sizeof(char))));
        }
        finally
        {
            NativeMethods.CredFree(pointer);
        }
    }

    private static ValueTask WriteTargetAsync(
        string target,
        string value,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(value);
        cancellationToken.ThrowIfCancellationRequested();
        EnsureWindows();
        var bytes = checked((uint)(value.Length * sizeof(char)));
        var pointer = Marshal.StringToCoTaskMemUni(value);
        try
        {
            var credential = new NativeCredential
            {
                Type = CredentialType.Generic,
                TargetName = target,
                CredentialBlobSize = bytes,
                CredentialBlob = pointer,
                Persist = CredentialPersistence.LocalMachine,
                UserName = "SIDEY",
            };
            if (!NativeMethods.CredWrite(ref credential, 0))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "Credential Manager write failed.");
            }

            return ValueTask.CompletedTask;
        }
        finally
        {
            Marshal.ZeroFreeCoTaskMemUnicode(pointer);
        }
    }

    private static ValueTask DeleteTargetAsync(string target, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        EnsureWindows();
        if (!NativeMethods.CredDelete(target, CredentialType.Generic, 0))
        {
            var error = Marshal.GetLastPInvokeError();
            if (error != NativeMethods.ErrorNotFound)
            {
                return ValueTask.FromException(new Win32Exception(
                    error,
                    "Credential Manager delete failed."));
            }
        }

        return ValueTask.CompletedTask;
    }

    private static string InviteTarget(Guid roomId) => $"{Prefix}Invite/{roomId:D}";

    private static void EnsureWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Windows Credential Manager is required.");
        }
    }

    private enum CredentialType : uint
    {
        Generic = 1,
    }

    private enum CredentialPersistence : uint
    {
        LocalMachine = 2,
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public CredentialType Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public nint CredentialBlob;
        public CredentialPersistence Persist;
        public uint AttributeCount;
        public nint Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    private static class NativeMethods
    {
        public const int ErrorNotFound = 1168;

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredRead(
            string target,
            CredentialType type,
            uint reservedFlag,
            out nint credential);

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredWrite(ref NativeCredential credential, uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredDelete(string target, CredentialType type, uint flags);

        [DllImport("advapi32.dll")]
        public static extern void CredFree(nint buffer);
    }
}
