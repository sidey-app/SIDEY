using System.Text.Json;

namespace Sidey.Infrastructure.Realtime;

internal sealed class RealtimeSubscriptionException(bool authorizationFailure)
    : Exception("Supabase Realtime subscription was rejected.")
{
    public bool AuthorizationFailure { get; } = authorizationFailure;

    public static RealtimeSubscriptionException FromServerPayload(JsonElement payload)
    {
        // Inspect only the documented error category. Never retain/log tokens, topics, or raw replies.
        string? reason = ExtractReason(payload);
        string? code = reason?.Split(':', 2)[0];
        return new(code is "Unauthorized" or "InvalidJWTToken" or "MalformedJWT" or "JwtSignatureError"
            || reason?.StartsWith("You do not have permissions", StringComparison.Ordinal) == true);
    }

    private static string? ExtractReason(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (payload.TryGetProperty("response", out JsonElement response)
            && response.ValueKind == JsonValueKind.Object
            && response.TryGetProperty("reason", out JsonElement responseReason)
            && responseReason.ValueKind == JsonValueKind.String)
        {
            return responseReason.GetString();
        }

        if (payload.TryGetProperty("reason", out JsonElement reason)
            && reason.ValueKind == JsonValueKind.String)
        {
            return reason.GetString();
        }

        if (payload.TryGetProperty("message", out JsonElement message)
            && message.ValueKind == JsonValueKind.String)
        {
            return message.GetString();
        }

        return null;
    }
}
