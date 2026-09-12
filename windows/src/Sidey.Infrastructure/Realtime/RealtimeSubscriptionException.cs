using System.Text.Json;

namespace Sidey.Infrastructure.Realtime;

internal sealed class RealtimeSubscriptionException(bool authorizationFailure)
    : Exception("Supabase Realtime subscription was rejected.")
{
    public bool AuthorizationFailure { get; } = authorizationFailure;

    public static RealtimeSubscriptionException FromReply(JsonElement payload)
    {
        // Inspect only the documented error category. Never retain/log tokens, topics, or raw replies.
        string? reason = payload.ValueKind == JsonValueKind.Object
            && payload.TryGetProperty("response", out JsonElement response)
            && response.ValueKind == JsonValueKind.Object
            && response.TryGetProperty("reason", out JsonElement value)
            && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        string? code = reason?.Split(':', 2)[0];
        return new(code is "Unauthorized" or "InvalidJWTToken" or "MalformedJWT" or "JwtSignatureError"
            || reason?.StartsWith("You do not have permissions", StringComparison.Ordinal) == true);
    }
}
