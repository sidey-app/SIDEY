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

        var characterAssets = project.Descendants("None").Single(element =>
            (string?)element.Attribute("Include") == "@(_SideyExternalCharacterAsset)");
        Assert.Equal("true", characterAssets.Element("ExcludeFromSingleFile")?.Value);
        Assert.Equal("PreserveNewest", characterAssets.Element("CopyToPublishDirectory")?.Value);
        Assert.DoesNotContain(
            project.Descendants("Content"),
            element => ((string?)element.Attribute("Include"))?.Contains(
                "Assets/Characters",
                StringComparison.Ordinal) == true);

        var keepExternal = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "KeepCharacterAssetsOutsideSingleFile");
        Assert.Equal("GenerateSingleFileBundle", (string?)keepExternal.Attribute("BeforeTargets"));
        Assert.Equal("PrepareForBundle", (string?)keepExternal.Attribute("DependsOnTargets"));
        Assert.Contains(
            "FullPath",
            keepExternal.Descendants("FilesToBundle").Single().Attribute("Remove")!.Value);

        var copyExternal = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalCharacterAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyExternal.Attribute("AfterTargets"));
        Assert.Equal(
            "$(PublishDir)Assets\\Characters",
            copyExternal.Descendants("Copy").Single().Attribute("DestinationFolder")?.Value);
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
    public void MsiSuppressesOnlyTheDocumentedSingleFileAndCommonMenuIceRules()
    {
        var project = XDocument.Load(AssetPath("Sidey.Msi.wixproj.xml"));

        Assert.Equal("ICE03;ICE38;ICE43;ICE57", Value(project, "SuppressIces"));
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
