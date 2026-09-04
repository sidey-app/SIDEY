using System.Reflection;
using System.Xml.Linq;
using Sidey.Presentation.ViewModels;

namespace Sidey.Presentation.Tests;

public sealed class MvvmArchitectureTests
{
    private static readonly string[] ForbiddenAssemblyPrefixes =
    [
        "Microsoft.UI",
        "Sidey.App",
        "Sidey.Infrastructure",
        "Sidey.Overlay",
        "Sidey.Platform.Windows",
    ];

    [Fact]
    public void PresentationProjectReferencesOnlyCoreAsAProductProject()
    {
        XDocument project = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.Presentation",
            "Sidey.Presentation.csproj"));

        string[] references = project
            .Descendants("ProjectReference")
            .Select(element => element.Attribute("Include")?.Value.Replace('\\', '/'))
            .Where(path => path is not null)
            .Cast<string>()
            .ToArray();

        Assert.Equal(["../Sidey.Core/Sidey.Core.csproj"], references);
    }

    [Fact]
    public void PresentationAssemblyDoesNotReferenceAppOrPlatformAssemblies()
    {
        Assembly presentation = typeof(MainWindowViewModel).Assembly;

        Assert.DoesNotContain(
            presentation.GetReferencedAssemblies(),
            reference => IsForbiddenAssembly(reference.Name));
    }

    [Fact]
    public void ViewModelPublicContractsDoNotExposeViewOrPlatformTypes()
    {
        Type[] viewModels = typeof(MainWindowViewModel).Assembly
            .GetTypes()
            .Where(type => type.Namespace == typeof(MainWindowViewModel).Namespace)
            .ToArray();

        foreach (Type viewModel in viewModels)
        {
            IEnumerable<Type> contractTypes = viewModel
                .GetConstructors(BindingFlags.Public | BindingFlags.Instance)
                .SelectMany(constructor => constructor.GetParameters())
                .Select(parameter => parameter.ParameterType)
                .Concat(viewModel
                    .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                    .Select(property => property.PropertyType));

            Assert.DoesNotContain(contractTypes, ContainsForbiddenType);
        }
    }

    [Theory]
    [InlineData("MainWindow.xaml", "SaveProfileCommand")]
    [InlineData("MainWindow.xaml", "CreateRoomCommand")]
    [InlineData("ComposerWindow.xaml", "SendCommand")]
    [InlineData("OnboardingWindow.xaml", "SkipGroupCommand")]
    public void ViewActionsUseCommandBindings(string fileName, string commandName)
    {
        XDocument view = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            fileName));

        Assert.Contains(
            view.Descendants().Attributes(),
            attribute => attribute.Name.LocalName == "Command"
                && attribute.Value == $"{{Binding {commandName}}}");
    }

    private static bool ContainsForbiddenType(Type type)
    {
        if (IsForbiddenAssembly(type.Assembly.GetName().Name)
            || type.Namespace?.StartsWith("Windows.", StringComparison.Ordinal) == true)
        {
            return true;
        }

        if (type.HasElementType && type.GetElementType() is { } elementType)
        {
            return ContainsForbiddenType(elementType);
        }

        return type.IsGenericType && type.GetGenericArguments().Any(ContainsForbiddenType);
    }

    private static bool IsForbiddenAssembly(string? name) =>
        name is not null
        && ForbiddenAssemblyPrefixes.Any(prefix => name.StartsWith(prefix, StringComparison.Ordinal));

    private static string RepositoryPath(params string[] pathSegments)
    {
        DirectoryInfo? root = new(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        return Path.Combine([root!.FullName, .. pathSegments]);
    }
}
