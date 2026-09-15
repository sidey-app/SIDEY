using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Authentication;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Realtime;

internal static class RealtimeUserErrorMessage
{
    public static string From(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            switch (current)
            {
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Authorization,
                }:
                    return I18n.Get("connection.accessRequired");
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Capacity,
                }:
                    return I18n.Get("connection.busy");
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Configuration,
                }:
                    return I18n.Get("connection.configurationUnavailable");
                case RealtimeSubscriptionException:
                    return I18n.Get("connection.serviceUnavailable");
                case HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests }:
                    return I18n.Get("connection.busy");
                case HttpRequestException { StatusCode: HttpStatusCode.Unauthorized }:
                    return I18n.Get("connection.accessRequired");
                case HttpRequestException
                {
                    StatusCode: HttpStatusCode.BadRequest or HttpStatusCode.Forbidden,
                }:
                    return I18n.Get("connection.configurationUnavailable");
                case UnauthorizedAccessException:
                    return I18n.Get("connection.accessRequired");
                case SocketException socketException
                    when IsLocalNetworkFailure(socketException.SocketErrorCode):
                    return I18n.Get("connection.networkUnavailable");
                case AuthenticationException:
                    return I18n.Get("connection.secureConnectionFailed");
            }
        }

        return I18n.Get("connection.serviceUnavailable");
    }

    public static bool IsExpectedLocalAbort(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is SocketException { SocketErrorCode: SocketError.OperationAborted })
            {
                return true;
            }
        }
        return false;
    }

    private static bool IsLocalNetworkFailure(SocketError error) => error is
        SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain
        or SocketError.NetworkDown or SocketError.NetworkUnreachable
        or SocketError.HostDown or SocketError.HostUnreachable;
}
