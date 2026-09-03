using System.Xml.Linq;

namespace Sidey.Platform.Windows.Tests;

public sealed class DistributionSourceTests
{
    [Fact]
    public void AppPublishIsMultiFileSelfContainedWithExternalAssets()
    {
        var project = XDocument.Load(AssetPath("Sidey.App.csproj.xml"));

        Assert.Equal("false", Value(project, "PublishSingleFile"));
        Assert.Equal("true", Value(project, "WindowsAppSDKSelfContained"));
        Assert.Equal("true", Value(project, "SelfContained"));
        Assert.Equal("true", Value(project, "EnableMsixTooling"));
        Assert.Equal("false", Value(project, "IncludeAllContentForSelfExtract"));
        Assert.Equal("false", Value(project, "PublishTrimmed"));
        Assert.Equal("1.0.5", Value(project, "Version"));
        Assert.Equal("1.0.5.0", Value(project, "FileVersion"));
        Assert.Equal("1.0.5.0", Value(project, "AssemblyVersion"));
        Assert.Equal("SIDEY.Host", Value(project, "AssemblyName"));
        Assert.Equal("SIDEY", Value(project, "AssemblyTitle"));
        Assert.Equal("SIDEY", Value(project, "Product"));

        Assert.Empty(project.Descendants("ExcludeFromSingleFile"));
        Assert.DoesNotContain(
            project.Descendants("Target"),
            element => ((string?)element.Attribute("Name"))?.Contains(
                "SingleFile",
                StringComparison.Ordinal) == true);

        var characterAssets = project.Descendants("None").Single(element =>
            (string?)element.Attribute("Include") == "@(_SideyExternalCharacterAsset)");
        Assert.Equal("PreserveNewest", characterAssets.Element("CopyToPublishDirectory")?.Value);
        Assert.DoesNotContain(
            project.Descendants("Content"),
            element => ((string?)element.Attribute("Include"))?.Contains(
                "Assets/Characters",
                StringComparison.Ordinal) == true);

        var copyExternal = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalCharacterAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyExternal.Attribute("AfterTargets"));
        Assert.Contains(
            "%(RecursiveDir)",
            copyExternal.Descendants("Copy").Single().Attribute("DestinationFiles")?.Value);

        var organize = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "OrganizeStructuredPublish");
        Assert.Equal("Publish", (string?)organize.Attribute("AfterTargets"));
        Assert.Contains(
            "organize-publish.ps1",
            organize.Descendants("Exec").Single().Attribute("Command")?.Value,
            StringComparison.Ordinal);
    }

    [Fact]
    public void OverlaySupportsTheUnpackagedSelfContainedApp()
    {
        var project = XDocument.Load(AssetPath("Sidey.Overlay.csproj.xml"));

        Assert.Equal("true", Value(project, "EnableMsixTooling"));
        Assert.Empty(project.Descendants("ExcludeFromSingleFile"));
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

        var files = package.Descendants(ns + "Files").Single();
        Assert.Equal(@"$(PublishDir)\**", (string?)files.Attribute("Include"));
        var excludedFiles = files
            .Elements(ns + "Exclude")
            .Select(exclude => (string?)exclude.Attribute("Files"))
            .ToArray();
        Assert.Contains(@"$(PublishDir)\**\*.pdb", excludedFiles);
        Assert.Contains(@"$(PublishDir)\SIDEY-Onboarding-Preview.cmd", excludedFiles);
        Assert.Contains(
            package.Descendants().Where(element => element.Name.LocalName == "RestartResource"),
            resource => (string?)resource.Attribute("ProcessName") == "SIDEY.Host.exe");
        Assert.Contains(
            package.Descendants(ns + "Directory"),
            directory => (string?)directory.Attribute("Id") == "LANGSFOLDER"
                && (string?)directory.Attribute("Name") == "Langs");
    }

    [Fact]
    public void MsiSuppressesOnlyTheDocumentedNativePeAndCommonMenuIceRules()
    {
        var project = XDocument.Load(AssetPath("Sidey.Msi.wixproj.xml"));

        Assert.Equal("ICE03;ICE38;ICE43;ICE57", Value(project, "SuppressIces"));
    }

    [Fact]
    public void MsiUsesThePublicVersionedFileName()
    {
        var project = XDocument.Load(AssetPath("Sidey.Msi.wixproj.xml"));

        Assert.Equal(
            "SIDEY-Windows-x64-v$(DisplayVersion)",
            Value(project, "OutputName"));
    }

    [Fact]
    public void MsiRunsSelectedUninstallerCleanupOnlyForOrdinaryUninstall()
    {
        var document = XDocument.Load(AssetPath("Sidey.Msi.Package.wxs"));
        var property = document.Descendants().Single(element =>
            element.Name.LocalName == "Property"
            && (string?)element.Attribute("Id") == "REMOVEUSERDATA");
        Assert.Equal("yes", (string?)property.Attribute("Secure"));
        Assert.Null(property.Attribute("Value"));

        var action = document.Descendants().Single(element =>
            element.Name.LocalName == "CustomAction"
            && (string?)element.Attribute("Id") == "RemoveCurrentUserData");
        Assert.Equal("deferred", (string?)action.Attribute("Execute"));
        Assert.Equal("yes", (string?)action.Attribute("Impersonate"));
        Assert.Equal("check", (string?)action.Attribute("Return"));
        Assert.Contains("Uninstall.exe", (string?)action.Attribute("ExeCommand"));
        Assert.Contains("--cleanup", (string?)action.Attribute("ExeCommand"));

        var scheduled = document.Descendants().Single(element =>
            element.Name.LocalName == "Custom"
            && (string?)element.Attribute("Action") == "RemoveCurrentUserData");
        var condition = (string?)scheduled.Attribute("Condition");
        Assert.Contains("REMOVE=\"ALL\"", condition, StringComparison.Ordinal);
        Assert.Contains("NOT UPGRADINGPRODUCTCODE", condition, StringComparison.Ordinal);
        Assert.Contains("REMOVEUSERDATA=\"1\"", condition, StringComparison.Ordinal);
        Assert.Equal("RemoveStartupValue", (string?)scheduled.Attribute("Before"));
    }

    [Fact]
    public void MsiRemovalDataOptionIsUncheckedByDefault()
    {
        var document = XDocument.Load(AssetPath("Sidey.Msi.SideyUI.wxs"));
        var checkbox = document.Descendants().Single(element =>
            element.Name.LocalName == "Control"
            && (string?)element.Attribute("Id") == "RemoveUserData");

        Assert.Equal("CheckBox", (string?)checkbox.Attribute("Type"));
        Assert.Equal("REMOVEUSERDATA", (string?)checkbox.Attribute("Property"));
        Assert.Equal("1", (string?)checkbox.Attribute("CheckBoxValue"));

        var removeNavigation = document.Descendants().Single(element =>
            element.Name.LocalName == "Publish"
            && (string?)element.Attribute("Dialog") == "MaintenanceTypeDlg"
            && (string?)element.Attribute("Control") == "RemoveButton");
        Assert.Equal("SideyRemoveDataDlg", (string?)removeNavigation.Attribute("Value"));

        var project = XDocument.Load(AssetPath("Sidey.Msi.wixproj.xml"));
        Assert.Contains(
            project.Descendants("PackageReference"),
            reference => (string?)reference.Attribute("Include") == "WixToolset.UI.wixext");
    }

    [Fact]
    public void InstalledUninstallerStartsMsiAndDeletesOnlySideyCurrentUserData()
    {
        string uninstaller = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Uninstaller", "Program.cs"));

        Assert.Contains("MsiEnumRelatedProducts", uninstaller, StringComparison.Ordinal);
        Assert.Contains("msiexec.exe", uninstaller, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("start.Verb = \"runas\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CleanupArgument = \"--cleanup\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredentialFilter = \"SIDEY/*\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredEnumerate", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredentialType.Generic", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Environment.SpecialFolder.LocalApplicationData", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Path.Combine(normalizedLocalAppData, \"SIDEY\")", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Directory.Delete(dataRoot, true)", uninstaller, StringComparison.Ordinal);
    }

    [Fact]
    public void MsiAndUninstallerUseTheSideyApplicationIcon()
    {
        var document = XDocument.Load(AssetPath("Sidey.Msi.Package.wxs"));
        var productIcon = document.Descendants().Single(element =>
            element.Name.LocalName == "Icon"
            && (string?)element.Attribute("Id") == "SideyProductIcon");
        Assert.EndsWith(
            @"Assets\Icons\SideyAppIcon.ico",
            (string?)productIcon.Attribute("SourceFile"),
            StringComparison.OrdinalIgnoreCase);

        var arpIcon = document.Descendants().Single(element =>
            element.Name.LocalName == "Property"
            && (string?)element.Attribute("Id") == "ARPPRODUCTICON");
        Assert.Equal("SideyProductIcon", (string?)arpIcon.Attribute("Value"));

        var uninstallShortcut = document.Descendants().Single(element =>
            element.Name.LocalName == "Shortcut"
            && (string?)element.Attribute("Id") == "UninstallShortcut");
        Assert.Equal("[INSTALLFOLDER]Uninstall.exe", (string?)uninstallShortcut.Attribute("Target"));

        string organizer = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "organize-publish.ps1"));
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("/win32icon", organizer, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DistributionPipelineBuildsOnlyThePublicMsiWithoutSelfSigning()
    {
        string package = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "package.ps1"));

        Assert.Contains("SIDEY-Windows-x64-v$Version.msi", package, StringComparison.Ordinal);
        Assert.Contains("Get-FileHash", package, StringComparison.Ordinal);
        Assert.Contains("SHA256=$hash", package, StringComparison.Ordinal);
        Assert.Contains("Runtime/SIDEY.Host.exe", package, StringComparison.Ordinal);
        Assert.Contains("Uninstall.exe", package, StringComparison.Ordinal);
        Assert.Contains("'SIDEY.Host.dll'", package, StringComparison.Ordinal);
        Assert.Contains("'Sidey.Core.dll'", package, StringComparison.Ordinal);
        Assert.Contains("'Sidey.Infrastructure.dll'", package, StringComparison.Ordinal);
        Assert.Contains("'Sidey.Overlay.dll'", package, StringComparison.Ordinal);
        Assert.Contains("'Sidey.Platform.Windows.dll'", package, StringComparison.Ordinal);
        Assert.Contains("'Sidey.Presentation.dll'", package, StringComparison.Ordinal);
        Assert.DoesNotContain("sign-self-signed", package, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Set-AuthenticodeSignature", package, StringComparison.Ordinal);
        Assert.DoesNotContain("SIDEY-SelfSigned", package, StringComparison.Ordinal);
        Assert.DoesNotContain("Setup.exe", package, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(".sha256", package, StringComparison.OrdinalIgnoreCase);
        Assert.False(File.Exists(RepositoryPath(
            "scripts", "windows", "sign-self-signed.ps1")));
        Assert.False(File.Exists(RepositoryPath(
            "windows", "installer", "Sidey.Bundle", "Bundle.wxs")));
        Assert.False(File.Exists(RepositoryPath(
            "windows", "installer", "Sidey.Bundle", "Sidey.Bundle.wixproj")));

        string organizer = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "organize-publish.ps1"));
        string launcher = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Launcher", "Program.cs"));
        Assert.Contains("SIDEY.Host.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("Runtime", organizer, StringComparison.Ordinal);
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("SIDEY.Host.exe", launcher, StringComparison.Ordinal);
    }

    private static string Value(XDocument document, string name) =>
        document.Descendants(name).Single().Value;

    private static string AssetPath(string name) =>
        Path.Combine(AppContext.BaseDirectory, "TestAssets", name);

    private static string RepositoryPath(params string[] pathSegments)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        return Path.Combine([root!.FullName, .. pathSegments]);
    }
}
