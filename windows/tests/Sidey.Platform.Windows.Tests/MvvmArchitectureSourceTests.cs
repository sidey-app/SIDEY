namespace Sidey.Platform.Windows.Tests;

public sealed class MvvmArchitectureSourceTests
{
    [Fact]
    public void ViewsBindUserActionsToViewModelCommands()
    {
        string main = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml");
        string composer = ReadRepositoryFile("windows", "src", "Sidey.App", "ComposerWindow.xaml");
        string history = ReadRepositoryFile("windows", "src", "Sidey.App", "HistoryWindow.xaml");

        Assert.Contains("Command=\"{Binding SaveProfileCommand}\"", main, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding CreateRoomCommand}\"", main, StringComparison.Ordinal);
        Assert.Contains("Command=\"{Binding SendCommand}\"", composer, StringComparison.Ordinal);
        Assert.Contains("ItemsSource=\"{Binding Items}\"", history, StringComparison.Ordinal);
        Assert.DoesNotContain("Click=", composer, StringComparison.Ordinal);
        Assert.DoesNotContain("Click=", history, StringComparison.Ordinal);
    }

    [Fact]
    public void MainWindowCodeBehindOnlyOwnsViewAndPlatformConcerns()
    {
        string source = ReadRepositoryFile("windows", "src", "Sidey.App", "MainWindow.xaml.cs");

        Assert.Contains("IMainWindowDialogService", source, StringComparison.Ordinal);
        Assert.Contains("MainWindowViewModel", source, StringComparison.Ordinal);
        Assert.DoesNotContain("AppCoordinator _", source, StringComparison.Ordinal);
        Assert.DoesNotContain("SaveProfileAsync(", source, StringComparison.Ordinal);
        Assert.DoesNotContain("CreateRoomAsync(", source, StringComparison.Ordinal);
        Assert.DoesNotContain("JoinRoomAsync(", source, StringComparison.Ordinal);
    }

    [Fact]
    public void ViewModelsDependOnCoordinatorAbstraction()
    {
        string main = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "MainWindowViewModel.cs");
        string history = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "HistoryWindowViewModel.cs");

        Assert.Contains("readonly ISideyCoordinator _coordinator", main, StringComparison.Ordinal);
        Assert.Contains("readonly ISideyCoordinator _coordinator", history, StringComparison.Ordinal);
        Assert.DoesNotContain("readonly AppCoordinator", main, StringComparison.Ordinal);
        Assert.DoesNotContain("readonly AppCoordinator", history, StringComparison.Ordinal);
    }

    [Fact]
    public void PresentationProjectDoesNotReferenceWinUiOrPlatformImplementations()
    {
        string project = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "Sidey.Presentation.csproj");
        string main = ReadRepositoryFile(
            "windows", "src", "Sidey.Presentation", "ViewModels", "MainWindowViewModel.cs");

        Assert.Contains("../Sidey.Core/Sidey.Core.csproj", project, StringComparison.Ordinal);
        Assert.DoesNotContain("Sidey.App", project, StringComparison.Ordinal);
        Assert.DoesNotContain("Sidey.Overlay", project, StringComparison.Ordinal);
        Assert.DoesNotContain("Sidey.Platform.Windows", project, StringComparison.Ordinal);
        Assert.DoesNotContain("Microsoft.UI", main, StringComparison.Ordinal);
        Assert.DoesNotContain("WindowsUpdateService", main, StringComparison.Ordinal);
    }

    private static string ReadRepositoryFile(params string[] pathSegments)
        => File.ReadAllText(RepositoryPath(pathSegments));

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
