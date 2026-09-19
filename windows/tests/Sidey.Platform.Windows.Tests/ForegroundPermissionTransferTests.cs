using System.IO.Pipes;
using System.Text;
using Sidey.App.Startup;

namespace Sidey.Platform.Windows.Tests;

public sealed class ForegroundPermissionTransferTests
{
    [Fact]
    public async Task SecondaryInstanceGrantsTheExactPipeServerAndStillDeliversActivation()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var foreground = new FakeSingleInstanceForegroundPermission
        {
            ServerProcessId = 4242,
        };
        var signal = Task.Run(() => SingleInstanceGuard.Signal(
            pipeName,
            "sidey://auth/google?code=test",
            foreground));
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(10));
        byte[] buffer = new byte[Encoding.UTF8.GetByteCount("sidey://auth/google?code=test")];
        await server.ReadExactlyAsync(buffer).AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        await signal.WaitAsync(TimeSpan.FromSeconds(15));

        Assert.Equal("sidey://auth/google?code=test", Encoding.UTF8.GetString(buffer));
        Assert.Equal([4242u], foreground.AllowedProcessIds);
    }

    [Fact]
    public async Task ForegroundGrantFailureDoesNotBlockActivationDelivery()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var foreground = new FakeSingleInstanceForegroundPermission
        {
            ServerProcessId = 4242,
            GrantException = new InvalidOperationException("denied"),
        };
        var signal = Task.Run(() => SingleInstanceGuard.Signal(
            pipeName,
            "activate",
            foreground));
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(10));
        byte[] buffer = new byte[Encoding.UTF8.GetByteCount("activate")];
        await server.ReadExactlyAsync(buffer).AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        await signal.WaitAsync(TimeSpan.FromSeconds(15));

        Assert.Equal("activate", Encoding.UTF8.GetString(buffer));
        Assert.Equal([4242u], foreground.AllowedProcessIds);
    }

    [Fact]
    public async Task NativePipeBoundaryReturnsTheConnectedServerProcess()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        using var client = new NamedPipeClientStream(
            ".",
            pipeName,
            PipeDirection.Out,
            PipeOptions.CurrentUserOnly);
        Task connection = server.WaitForConnectionAsync();

        await client.ConnectAsync().WaitAsync(TimeSpan.FromSeconds(10));
        await connection.WaitAsync(TimeSpan.FromSeconds(10));
        var foreground = new NativeSingleInstanceForegroundPermission();

        Assert.True(foreground.TryGetServerProcessId(client, out uint serverProcessId));
        Assert.Equal((uint)Environment.ProcessId, serverProcessId);
    }

    [Fact]
    public void LauncherGrantsTheExactChildProcessWithoutUsingTheWildcard()
    {
        var api = new FakeLauncherForegroundPermissionApi();

        LauncherForegroundPermission.TryGrantToProcess(7319, api);

        Assert.Equal([7319u], api.AllowedProcessIds);
        Assert.DoesNotContain(uint.MaxValue, api.AllowedProcessIds);
    }

    [Fact]
    public void LauncherGrantFailureDoesNotEscapeToBlockHostStartup()
    {
        var api = new FakeLauncherForegroundPermissionApi
        {
            GrantException = new InvalidOperationException("denied"),
        };

        LauncherForegroundPermission.TryGrantToProcess(7319, api);

        Assert.Equal([7319u], api.AllowedProcessIds);
    }

    private sealed class FakeSingleInstanceForegroundPermission : ISingleInstanceForegroundPermission
    {
        internal uint ServerProcessId { get; init; }

        internal Exception? GrantException { get; init; }

        internal List<uint> AllowedProcessIds { get; } = [];

        public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId)
        {
            _ = pipe;
            processId = ServerProcessId;
            return true;
        }

        public bool AllowSetForegroundWindow(uint processId)
        {
            AllowedProcessIds.Add(processId);
            if (GrantException is not null)
            {
                throw GrantException;
            }
            return true;
        }
    }

    private sealed class FakeLauncherForegroundPermissionApi : ILauncherForegroundPermissionApi
    {
        internal Exception? GrantException { get; init; }

        internal List<uint> AllowedProcessIds { get; } = [];

        public bool AllowSetForegroundWindow(uint processId)
        {
            AllowedProcessIds.Add(processId);
            if (GrantException is not null)
            {
                throw GrantException;
            }
            return true;
        }
    }
}
