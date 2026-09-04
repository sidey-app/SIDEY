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
        Assert.Equal("1.0.6", Value(project, "Version"));
        Assert.Equal("1.0.6.0", Value(project, "FileVersion"));
        Assert.Equal("1.0.6.0", Value(project, "AssemblyVersion"));
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
                "Assets/Character",
                StringComparison.Ordinal) == true);

        var throwableAssets = project.Descendants("None").Single(element =>
            (string?)element.Attribute("Include") == "@(_SideyExternalThrowableAsset)");
        Assert.Equal("PreserveNewest", throwableAssets.Element("CopyToPublishDirectory")?.Value);

        var copyExternal = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalCharacterAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyExternal.Attribute("AfterTargets"));
        Assert.Contains(
            "%(RecursiveDir)",
            copyExternal.Descendants("Copy").Single().Attribute("DestinationFiles")?.Value);

        var copyThrowables = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalThrowableAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyThrowables.Attribute("AfterTargets"));
        Assert.Contains(
            "Assets\\Throwable",
            copyThrowables.Descendants("Copy").Single().Attribute("DestinationFiles")?.Value,
            StringComparison.Ordinal);

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
    public void SetupExeOffersAnInstallLocationAndReusesItForUpdates()
    {
        string setup = ReadSetupScript();

        Assert.Contains("InstallDir \"$PROGRAMFILES64\\SIDEY\"", setup, StringComparison.Ordinal);
        Assert.Contains("InstallDirRegKey HKLM", setup, StringComparison.Ordinal);
        Assert.Contains("RequestExecutionLevel admin", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_PAGE_DIRECTORY", setup, StringComparison.Ordinal);
        Assert.Contains("StrCpy $InstallState \"upgrade\"", setup, StringComparison.Ordinal);
        Assert.Contains("$InstallState == \"repair\"", setup, StringComparison.Ordinal);
        Assert.Contains("StrCpy $HasNsisInstall \"true\"", setup, StringComparison.Ordinal);
        Assert.Contains("ExecWait '\"$INSTDIR\\Uninstall.exe\" /S'", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void SetupExeSupportsEnglishAndKorean()
    {
        string setup = ReadSetupScript();

        Assert.Contains("MUI_LANGUAGE \"English\"", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_LANGUAGE \"Korean\"", setup, StringComparison.Ordinal);
        Assert.Contains("SetFont /LANG=${LANG_ENGLISH} \"Segoe UI\" 9", setup, StringComparison.Ordinal);
        Assert.Contains("SetFont /LANG=${LANG_KOREAN} \"맑은 고딕\" 9", setup, StringComparison.Ordinal);
        Assert.Contains("LangString MaintenanceTitle ${LANG_ENGLISH}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString MaintenanceTitle ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString DeleteLocalData ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString DeleteCredentials ${LANG_KOREAN}", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void FreshInstallAndUpgradeRequireTermsAcceptance()
    {
        string setup = ReadSetupScript();
        string package = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "package.ps1"));
        string generator = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "generate-installer-terms.ps1"));

        Assert.Contains("MUI_LICENSEPAGE_CHECKBOX", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_LICENSEPAGE_CHECKBOX_TEXT \"$(AcceptTerms)\"", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_PAGE_LICENSE \"${TERMS_LICENSE_FILE}\"", setup, StringComparison.Ordinal);
        Assert.Contains("LangString AcceptTerms ${LANG_ENGLISH}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString AcceptTerms ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("Function TermsPagePre", setup, StringComparison.Ordinal);
        Assert.Contains("$InstallState == \"repair\"", setup, StringComparison.Ordinal);
        Assert.Contains("generate-installer-terms.ps1", package, StringComparison.Ordinal);
        Assert.Contains("/DTERMS_LICENSE_FILE=", package, StringComparison.Ordinal);
        Assert.Contains("termsBytes[0] -ne 0xEF", package, StringComparison.Ordinal);
        Assert.Contains("[Text.UTF8Encoding]::new($true, $true)", package, StringComparison.Ordinal);
        Assert.Contains("[Text.UTF8Encoding]::new($true)", generator, StringComparison.Ordinal);
    }

    [Fact]
    public void SetupExeUsesAWhiteSideyWelcomeBitmap()
    {
        string setup = ReadSetupScript();
        byte[] bitmap = File.ReadAllBytes(RepositoryPath(
            "windows", "installer", "Sidey.Setup", "SideyWelcome.bmp"));

        Assert.Contains("MUI_WELCOMEFINISHPAGE_BITMAP", setup, StringComparison.Ordinal);
        Assert.Contains("SideyWelcome.bmp", setup, StringComparison.Ordinal);
        Assert.Equal((byte)'B', bitmap[0]);
        Assert.Equal((byte)'M', bitmap[1]);
        Assert.Equal(164, BitConverter.ToInt32(bitmap, 18));
        Assert.Equal(314, BitConverter.ToInt32(bitmap, 22));
        Assert.Equal(24, BitConverter.ToInt16(bitmap, 28));
    }

    [Fact]
    public void SameVersionOffersRepairRemoveAndCloseWhileDowngradesAreBlocked()
    {
        string setup = ReadSetupScript();

        Assert.Contains("${VersionCompare}", setup, StringComparison.Ordinal);
        Assert.Contains("StrCpy $InstallState \"same\"", setup, StringComparison.Ordinal);
        Assert.Contains("${NSD_CreateButton}", setup, StringComparison.Ordinal);
        Assert.Contains("$(RepairAction)", setup, StringComparison.Ordinal);
        Assert.Contains("$(RemoveAction)", setup, StringComparison.Ordinal);
        Assert.Contains("$(CloseAction)", setup, StringComparison.Ordinal);
        Assert.Contains("StrCpy $InstallState \"remove\"", setup, StringComparison.Ordinal);
        Assert.Contains("StrCpy $InstallState \"close\"", setup, StringComparison.Ordinal);
        Assert.Contains("HideWindow", setup, StringComparison.Ordinal);
        Assert.Contains("ExecWait '\"$INSTDIR\\Uninstall.exe\"'", setup, StringComparison.Ordinal);
        Assert.Contains("$(DowngradeBlocked)", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void UninstallCleanupChoicesAreIndependentAndUncheckedByDefault()
    {
        string setup = ReadSetupScript();

        Assert.Contains("${NSD_Uncheck} $DeleteLocalDataCheckbox", setup, StringComparison.Ordinal);
        Assert.Contains("${NSD_Uncheck} $DeleteCredentialsCheckbox", setup, StringComparison.Ordinal);
        Assert.Contains("--cleanup-local-data", setup, StringComparison.Ordinal);
        Assert.Contains("$DeleteLocalData == ${BST_CHECKED}", setup, StringComparison.Ordinal);
        Assert.Contains("--cleanup-credentials", setup, StringComparison.Ordinal);
        Assert.Contains("$DeleteCredentials == ${BST_CHECKED}", setup, StringComparison.Ordinal);
        Assert.DoesNotContain("RMDir /r \"$LOCALAPPDATA", setup, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SetupMigratesTheLegacyMsiWithoutDeletingUserData()
    {
        string setup = ReadSetupScript();
        string uninstaller = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Uninstaller", "Program.cs"));

        Assert.Contains("LEGACY_MSI_UPGRADE_CODE", setup, StringComparison.Ordinal);
        Assert.Contains("--uninstall-legacy-msi", setup, StringComparison.Ordinal);
        Assert.Contains("SideyLegacyMsiHelper.exe", setup, StringComparison.Ordinal);
        Assert.Contains("/quiet /norestart", uninstaller, StringComparison.Ordinal);
        Assert.Contains("MsiEnumRelatedProducts", uninstaller, StringComparison.Ordinal);
        Assert.DoesNotContain("--cleanup", setup[..setup.IndexOf("Section \"Uninstall\"", StringComparison.Ordinal)], StringComparison.Ordinal);
        Assert.Contains("$0 == 3010", setup, StringComparison.Ordinal);
        Assert.Contains("$(LegacyMigrationRestart)", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void InstalledNsisUninstallerDeletesOnlySelectedCurrentUserData()
    {
        string uninstaller = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Uninstaller", "Program.cs"));

        string setup = ReadSetupScript();

        Assert.Contains("WriteUninstaller \"$INSTDIR\\Uninstall.exe\"", setup, StringComparison.Ordinal);
        Assert.Contains("SIDEY.UninstallHelper.exe", setup, StringComparison.Ordinal);
        Assert.Contains("CleanupLocalDataArgument = \"--cleanup-local-data\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CleanupCredentialsArgument = \"--cleanup-credentials\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredentialFilter = \"SIDEY/*\"", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredEnumerate", uninstaller, StringComparison.Ordinal);
        Assert.Contains("CredentialType.Generic", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Environment.SpecialFolder.LocalApplicationData", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Path.Combine(normalizedLocalAppData, \"SIDEY\")", uninstaller, StringComparison.Ordinal);
        Assert.Contains("Directory.Delete(dataRoot, true)", uninstaller, StringComparison.Ordinal);
    }

    [Fact]
    public void SetupAndUninstallerUseTheSideyApplicationIcon()
    {
        string setup = ReadSetupScript();

        Assert.Contains(
            "Icon \"${PUBLISH_DIR}\\Assets\\Icons\\SideyAppIcon.ico\"",
            setup,
            StringComparison.Ordinal);
        Assert.Contains(
            "UninstallIcon \"${PUBLISH_DIR}\\Assets\\Icons\\SideyAppIcon.ico\"",
            setup,
            StringComparison.Ordinal);
        Assert.Contains("WriteUninstaller \"$INSTDIR\\Uninstall.exe\"", setup, StringComparison.Ordinal);

        string organizer = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "organize-publish.ps1"));
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("/win32icon", organizer, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DistributionPipelineBuildsOnlyThePublicSetupExeWithoutSelfSigning()
    {
        string package = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "package.ps1"));

        Assert.Contains("SIDEY-Windows-x64-v${Version}-Setup.exe", package, StringComparison.Ordinal);
        Assert.Contains("NSIS 3.12", package, StringComparison.Ordinal);
        Assert.Contains("makensis.exe", package, StringComparison.Ordinal);
        Assert.Contains("/VERSION", package, StringComparison.Ordinal);
        Assert.Contains("SideyPayloadInstall.nsh", package, StringComparison.Ordinal);
        Assert.Contains("SideyPayloadUninstall.nsh", package, StringComparison.Ordinal);
        Assert.Contains("Generated NSIS payload paths must expand $INSTDIR", package, StringComparison.Ordinal);
        Assert.DoesNotContain("ConvertTo-NsisLiteral $destination", package, StringComparison.Ordinal);
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
        Assert.DoesNotContain(".msi", package, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(".sha256", package, StringComparison.OrdinalIgnoreCase);
        Assert.False(File.Exists(RepositoryPath(
            "windows", "installer", "Sidey.Msi", "Sidey.Msi.wixproj")));

        string organizer = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "organize-publish.ps1"));
        string launcher = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Launcher", "Program.cs"));
        Assert.Contains("SIDEY.Host.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("Runtime", organizer, StringComparison.Ordinal);
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("SIDEY.Host.exe", launcher, StringComparison.Ordinal);
    }

    private static string ReadSetupScript() => File.ReadAllText(AssetPath("Sidey.Setup.nsi"));

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
