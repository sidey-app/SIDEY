using System.Xml.Linq;

namespace Sidey.Platform.Windows.Tests;

public sealed class DistributionSourceTests
{
    [Fact]
    public void AppPublishIsSingleFileButCharactersStayExternal()
    {
        var project = XDocument.Load(AssetPath("Sidey.App.csproj.xml"));

        Assert.Equal("true", Value(project, "PublishSingleFile"));
        Assert.Equal("true", Value(project, "WindowsAppSDKSelfContained"));
        Assert.Equal("true", Value(project, "SelfContained"));
        Assert.Equal("true", Value(project, "EnableMsixTooling"));
        Assert.Equal("true", Value(project, "IncludeAllContentForSelfExtract"));
        Assert.Equal("false", Value(project, "PublishTrimmed"));

        var characterContent = project
            .Descendants("Content")
            .Single(element => ((string?)element.Attribute("Include"))?.Contains(
                "Assets/Characters",
                StringComparison.Ordinal) == true);
        Assert.Equal("true", characterContent.Element("ExcludeFromSingleFile")?.Value);
        Assert.Equal("PreserveNewest", characterContent.Element("CopyToPublishDirectory")?.Value);
    }

    [Fact]
    public void OverlaySupportsTheSingleFilePublishPropagatedFromTheApp()
    {
        var project = XDocument.Load(AssetPath("Sidey.Overlay.csproj.xml"));

        Assert.Equal("true", Value(project, "EnableMsixTooling"));
    }

    [Fact]
    public void MsiInstallsPerMachineIntoNativeProgramFiles()
    {
        var document = XDocument.Load(AssetPath("Sidey.Msi.Package.wxs"));
        var ns = document.Root!.Name.Namespace;
        var package = document.Root.Element(ns + "Package")!;

        Assert.Equal("perMachine", (string?)package.Attribute("Scope"));
        Assert.Contains(
            package.Elements(ns + "StandardDirectory"),
            directory => (string?)directory.Attribute("Id") == "ProgramFiles6432Folder");
        Assert.DoesNotContain(
            package.Elements(ns + "StandardDirectory"),
            directory => (string?)directory.Attribute("Id") == "LocalAppDataFolder");

        var installerMarker = package
            .Descendants(ns + "RegistryValue")
            .Single(value => (string?)value.Attribute("Name") == "InstalledVersion");
        Assert.Equal("HKLM", (string?)installerMarker.Attribute("Root"));
        Assert.Contains(
            package.Elements(ns + "Launch"),
            launch => ((string?)launch.Attribute("Condition"))?.Contains(
                "LEGACYUSERINSTALLVERSION",
                StringComparison.Ordinal) == true);
    }

    [Fact]
    public void BurnLaunchesTheProgramFilesExecutable()
    {
        var document = XDocument.Load(AssetPath("Sidey.Bundle.Bundle.wxs"));
        var launchTarget = document
            .Descendants()
            .Attributes("LaunchTarget")
            .Single()
            .Value;

        Assert.Equal("[ProgramFiles64Folder]SIDEY\\SIDEY.exe", launchTarget);
        Assert.DoesNotContain("LocalAppDataFolder", launchTarget, StringComparison.Ordinal);
    }

    private static string Value(XDocument document, string name) =>
        document.Descendants(name).Single().Value;

    private static string AssetPath(string name) =>
        Path.Combine(AppContext.BaseDirectory, "TestAssets", name);
}
