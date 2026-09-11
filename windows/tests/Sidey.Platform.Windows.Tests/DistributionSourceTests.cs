using System.Xml.Linq;

namespace Sidey.Platform.Windows.Tests;

public sealed class DistributionSourceTests
{
    [Fact]
    public void AppPublishIsMultiFileFrameworkDependentWithExternalAssets()
    {
        var project = XDocument.Load(AssetPath("Sidey.App.csproj.xml"));

        Assert.Equal("false", Value(project, "PublishSingleFile"));
        Assert.Equal("false", Value(project, "WindowsAppSDKSelfContained"));
        Assert.Equal("false", Value(project, "SelfContained"));
        Assert.Equal("true", Value(project, "WindowsAppSdkBootstrapInitialize"));
        Assert.Equal("true", Value(project, "EnableMsixTooling"));
        Assert.Equal("false", Value(project, "IncludeAllContentForSelfExtract"));
        Assert.Equal("false", Value(project, "PublishTrimmed"));
        Assert.Equal("1.2.0", Value(project, "Version"));
        Assert.Equal("1.2.0.0", Value(project, "FileVersion"));
        Assert.Equal("1.2.0.0", Value(project, "AssemblyVersion"));
        Assert.Equal("SIDEY.Host", Value(project, "AssemblyName"));
        Assert.Equal("SIDEY", Value(project, "AssemblyTitle"));
        Assert.Equal("SIDEY", Value(project, "Product"));

        Assert.Empty(project.Descendants("ExcludeFromSingleFile"));
        Assert.DoesNotContain(
            project.Descendants("Target"),
            element => ((string?)element.Attribute("Name"))?.Contains(
                "SingleFile",
                StringComparison.Ordinal) == true);

        XElement characterAssets = project.Descendants("None").Single(element =>
            (string?)element.Attribute("Include") == "@(_SideyExternalCharacterAsset)");
        Assert.Equal("PreserveNewest", characterAssets.Element("CopyToPublishDirectory")?.Value);
        Assert.DoesNotContain(
            project.Descendants("Content"),
            element => ((string?)element.Attribute("Include"))?.Contains(
                "Assets/Characters",
                StringComparison.Ordinal) == true);

        XElement throwableAssets = project.Descendants("None").Single(element =>
            (string?)element.Attribute("Include") == "@(_SideyExternalThrowableAsset)");
        Assert.Equal("PreserveNewest", throwableAssets.Element("CopyToPublishDirectory")?.Value);

        XElement copyExternal = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalCharacterAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyExternal.Attribute("AfterTargets"));
        Assert.Contains(
            "%(RecursiveDir)",
            copyExternal.Descendants("Copy").Single().Attribute("DestinationFiles")?.Value);

        XElement copyThrowables = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "CopyExternalThrowableAssetsAfterPublish");
        Assert.Equal("Publish", (string?)copyThrowables.Attribute("AfterTargets"));
        Assert.Contains(
            "Assets\\Throwables",
            copyThrowables.Descendants("Copy").Single().Attribute("DestinationFiles")?.Value,
            StringComparison.Ordinal);

        XElement organize = project.Descendants("Target").Single(element =>
            (string?)element.Attribute("Name") == "OrganizeStructuredPublish");
        Assert.Equal("Publish", (string?)organize.Attribute("AfterTargets"));
        Assert.Contains(
            "ConvertTo-PublishLayout.ps1",
            organize.Descendants("Exec").Single().Attribute("Command")?.Value,
            StringComparison.Ordinal);
    }

    [Fact]
    public void OverlaySupportsTheUnpackagedApp()
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
        Assert.Contains(
            "ExecWait '\"$INSTDIR\\Uninstall.exe\" /S _?=$INSTDIR'",
            setup,
            StringComparison.Ordinal);
    }

    [Fact]
    public void SetupExeSupportsAllSevenInstallerLanguages()
    {
        string setup = ReadSetupScript();

        Assert.Contains("MUI_LANGUAGE \"English\"", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_LANGUAGE \"Korean\"", setup, StringComparison.Ordinal);
        foreach (string language in new[] { "Japanese", "SimpChinese", "TradChinese", "Russian", "Ukrainian" })
        {
            Assert.Contains($"MUI_LANGUAGE \"{language}\"", setup, StringComparison.Ordinal);
        }
        Assert.Contains("Call SelectInstallerLanguage", setup, StringComparison.Ordinal);
        Assert.DoesNotContain("MUI_LANGDLL_DISPLAY", setup, StringComparison.Ordinal);
        Assert.Contains("WriteRegStr HKLM \"${PRODUCT_REGISTRY_KEY}\" \"Language\" $LANGUAGE", setup, StringComparison.Ordinal);
        Assert.Contains("SetFont /LANG=${LANG_ENGLISH} \"Segoe UI\" 9", setup, StringComparison.Ordinal);
        Assert.Contains("SetFont /LANG=${LANG_KOREAN} \"맑은 고딕\" 9", setup, StringComparison.Ordinal);
        Assert.Contains("LangString MaintenanceTitle ${LANG_ENGLISH}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString MaintenanceTitle ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString DeleteLocalData ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString DeleteCredentials ${LANG_KOREAN}", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void PublicLauncherPassesTheInstallerLanguageToTheApp()
    {
        string launcher = File.ReadAllText(RepositoryPath(
            "windows", "src", "Sidey.Launcher", "Program.cs"));
        string organizer = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "ConvertTo-PublishLayout.ps1"));

        Assert.Contains("RegistryHive.LocalMachine", launcher, StringComparison.Ordinal);
        Assert.Contains("RegistryView.Registry64", launcher, StringComparison.Ordinal);
        Assert.Contains("InstallerLanguages.AppLanguage", launcher, StringComparison.Ordinal);
        Assert.Contains("start.EnvironmentVariables[LanguageEnvironmentVariable] = language", launcher, StringComparison.Ordinal);
        Assert.Contains("InstallerLanguages.cs", organizer, StringComparison.Ordinal);
    }

    [Fact]
    public void InstallerRegistersOnlyTheProductionGoogleCallbackScheme()
    {
        string setup = ReadSetupScript();

        Assert.Contains("Software\\Classes\\sidey", setup, StringComparison.Ordinal);
        Assert.Contains("URL:SIDEY authentication callback", setup, StringComparison.Ordinal);
        Assert.Contains("$INSTDIR\\SIDEY.exe$", setup, StringComparison.Ordinal);
        Assert.DoesNotContain("Software\\Classes\\sidey-dev", setup, StringComparison.Ordinal);
        Assert.Contains("DeleteRegKey HKLM \"${PRODUCT_PROTOCOL_KEY}\"", setup, StringComparison.Ordinal);
    }

    [Fact]
    public void DevelopmentCommerceCanOnlyBeCompiledIntoExplicitDebugBuilds()
    {
        string props = File.ReadAllText(RepositoryPath("windows", "Directory.Build.props"));

        Assert.Contains("'$(Configuration)' == 'Debug'", props, StringComparison.Ordinal);
        Assert.Contains("'$(SideyDevelopmentCommerce)' == 'true'", props, StringComparison.Ordinal);
        Assert.Contains("SIDEY_DEVELOPMENT_COMMERCE", props, StringComparison.Ordinal);
        Assert.Contains("RejectDevelopmentCommerceOutsideDebug", props, StringComparison.Ordinal);
    }

    [Fact]
    public void FreshInstallAndUpgradeRequireTermsAcceptance()
    {
        string setup = ReadSetupScript();
        string package = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "New-WindowsInstaller.ps1"));
        string generator = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "New-InstallerTerms.ps1"));

        Assert.Contains("MUI_LICENSEPAGE_CHECKBOX", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_LICENSEPAGE_CHECKBOX_TEXT \"$(AcceptTerms)\"", setup, StringComparison.Ordinal);
        Assert.Contains("MUI_PAGE_LICENSE \"${TERMS_LICENSE_FILE}\"", setup, StringComparison.Ordinal);
        Assert.Contains("LangString AcceptTerms ${LANG_ENGLISH}", setup, StringComparison.Ordinal);
        Assert.Contains("LangString AcceptTerms ${LANG_KOREAN}", setup, StringComparison.Ordinal);
        Assert.Contains("Function TermsPagePre", setup, StringComparison.Ordinal);
        Assert.Contains("$InstallState == \"repair\"", setup, StringComparison.Ordinal);
        Assert.Contains("New-InstallerTerms.ps1", package, StringComparison.Ordinal);
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
    public void UninstallAlwaysRemovesEveryInstallerOwnedRegistryEntry()
    {
        string setup = ReadSetupScript();
        string uninstall = setup[setup.IndexOf("Section \"Uninstall\"", StringComparison.Ordinal)..];

        Assert.Contains(
            "DeleteRegValue HKCU \"Software\\Microsoft\\Windows\\CurrentVersion\\Run\" \"SIDEY\"",
            uninstall,
            StringComparison.Ordinal);
        Assert.Contains("DeleteRegKey HKLM \"${PRODUCT_UNINSTALL_KEY}\"", uninstall, StringComparison.Ordinal);
        Assert.Contains("DeleteRegKey HKLM \"${PRODUCT_PROTOCOL_KEY}\"", uninstall, StringComparison.Ordinal);
        Assert.Contains("DeleteRegKey HKLM \"${PRODUCT_REGISTRY_KEY}\"", uninstall, StringComparison.Ordinal);
    }

    [Fact]
    public void SetupMigratesTheLegacyMsiWithoutDeletingUserData()
    {
        string setup = ReadSetupScript();

        Assert.Contains("LEGACY_MSI_UPGRADE_CODE", setup, StringComparison.Ordinal);
        Assert.Contains("--uninstall-legacy-msi", setup, StringComparison.Ordinal);
        Assert.Contains("SideyLegacyMsiHelper.exe", setup, StringComparison.Ordinal);
        Assert.DoesNotContain("--cleanup", setup[..setup.IndexOf("Section \"Uninstall\"", StringComparison.Ordinal)], StringComparison.Ordinal);
        Assert.Contains("$0 == 3010", setup, StringComparison.Ordinal);
        Assert.Contains("$(LegacyMigrationRestart)", setup, StringComparison.Ordinal);
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
            "scripts", "windows", "ConvertTo-PublishLayout.ps1"));
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("/win32icon", organizer, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DistributionPipelineBuildsOnlyThePublicSetupExeWithoutSelfSigning()
    {
        string package = File.ReadAllText(RepositoryPath(
            "scripts", "windows", "New-WindowsInstaller.ps1"));

        Assert.Contains("$throwableDirectory.Name -eq 'throwable_toy_cannon'", package, StringComparison.Ordinal);
        Assert.Contains("@('emitter.bgra', 'emitter.png', 'preview.png')", package, StringComparison.Ordinal);
        Assert.Contains("Compare-Object $expectedFileNames $fileNames", package, StringComparison.Ordinal);
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
            "scripts", "windows", "ConvertTo-PublishLayout.ps1"));
        Assert.Contains("SIDEY.Host.exe", organizer, StringComparison.Ordinal);
        Assert.Contains("Runtime", organizer, StringComparison.Ordinal);
        Assert.Contains("Uninstall.exe", organizer, StringComparison.Ordinal);
    }

    private static string ReadSetupScript() => File.ReadAllText(AssetPath("Sidey.Setup.nsi"));

    [Fact]
    public void PrerequisitesFinishBeforeStoppingOrRemovingTheExistingApp()
    {
        string setup = ReadSetupScript();
        string section = setup[setup.IndexOf("Section \"SIDEY\" MainSection", StringComparison.Ordinal)..];
        string[] operations =
        [
            "Call EnsurePrerequisites",
            "Call StopSideyProcesses",
            "ExecWait '\"$INSTDIR\\Uninstall.exe\" /S _?=$INSTDIR'",
            "--uninstall-legacy-msi",
            "-InstallDirectory \"$INSTDIR\"",
            "!include \"${PAYLOAD_INSTALL_INCLUDE}\"",
        ];
        int previous = -1;
        foreach (string operation in operations)
        {
            int position = section.IndexOf(operation, StringComparison.Ordinal);
            Assert.True(position > previous, $"Expected operation after the previous step: {operation}");
            previous = position;
        }

        int start = setup.IndexOf("Function EnsurePrerequisites", StringComparison.Ordinal);
        string prerequisiteFunction = setup[start..setup.IndexOf("FunctionEnd", start, StringComparison.Ordinal)];
        Assert.Contains("-ProvisionAllUsers", prerequisiteFunction, StringComparison.Ordinal);
        Assert.Contains("$0 == 3010", prerequisiteFunction, StringComparison.Ordinal);
        Assert.Contains("$0 != 0", prerequisiteFunction, StringComparison.Ordinal);
        Assert.Equal(2, prerequisiteFunction.Split("    Abort", StringSplitOptions.None).Length - 1);

        string uninstall = setup[setup.IndexOf("Section \"Uninstall\"", StringComparison.Ordinal)..];
        Assert.DoesNotContain("SetupRuntime.ps1", uninstall, StringComparison.Ordinal);
        Assert.DoesNotContain("EnsurePrerequisites", uninstall, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxPackage", uninstall, StringComparison.Ordinal);
        Assert.DoesNotContain("$PROGRAMFILES64\\dotnet", uninstall, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("windows.yml")]
    [InlineData("windows-release.yml")]
    public void CiValidatesPublishedFilesAndInstallsRuntimesBeforeSmoke(string workflowName)
    {
        string workflow = File.ReadAllText(RepositoryPath(".github", "workflows", workflowName));
        Assert.Contains("--self-contained false", workflow, StringComparison.Ordinal);
        Assert.Contains("-p:WindowsAppSDKSelfContained=false", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("--self-contained true", workflow, StringComparison.Ordinal);
        Assert.Contains("Test-RuntimePrerequisites.ps1", workflow, StringComparison.Ordinal);
        int verification = workflow.IndexOf("Test-FrameworkDependentPublish.ps1", StringComparison.Ordinal);
        int prerequisites = workflow.IndexOf("SetupRuntime.ps1", StringComparison.Ordinal);
        int smoke = workflow.IndexOf("Test-PublishedApplication.ps1", StringComparison.Ordinal);
        Assert.True(verification >= 0 && prerequisites > verification && smoke > prerequisites);
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
