namespace Sidey.Overlay;

internal static class OverlayPlacementPolicy
{
    internal const long TargetSalt = unchecked((long)0x9E3779B97F4A7C15UL);

    internal static long CreateSessionSeed(long installationSeed) =>
        CombineSeed(installationSeed, Random.Shared.NextInt64());

    internal static long CombineSeed(long installationSeed, long sessionEntropy) =>
        installationSeed ^ sessionEntropy;

    internal static int RandomSeed(long sessionSeed) =>
        unchecked((int)(sessionSeed ^ (sessionSeed >> 32)));

    internal static double Fraction(Guid id, long sessionSeed, long salt = 0)
    {
        var bytes = id.ToByteArray();
        var value = BitConverter.ToUInt64(bytes, 0)
            ^ BitConverter.ToUInt64(bytes, 8)
            ^ unchecked((ulong)(sessionSeed ^ salt));
        value ^= value >> 33;
        value *= 0xff51afd7ed558ccdUL;
        value ^= value >> 33;
        return (value & 0x1FFFFFFFFFFFFFUL) / (double)0x20000000000000UL;
    }
}
