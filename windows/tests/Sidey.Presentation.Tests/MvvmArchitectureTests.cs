using System.Reflection;
using System.Xml.Linq;
using Sidey.Presentation.ViewModels;

namespace Sidey.Presentation.Tests;

public sealed class MvvmArchitectureTests
{
    private static readonly string[] s_forbiddenAssemblyPrefixes =
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
        var project = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.Presentation",
            "Sidey.Presentation.csproj"));

        string[] references = [.. project
            .Descendants("ProjectReference")
            .Select(element => element.Attribute("Include")?.Value.Replace('\\', '/'))
            .Where(path => path is not null)
            .Cast<string>()];

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
        Type[] viewModels = [.. typeof(MainWindowViewModel).Assembly
            .GetTypes()
            .Where(type => type.Namespace == typeof(MainWindowViewModel).Namespace)];

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
        var view = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "Views",
            fileName));

        Assert.Contains(
            view.Descendants().Attributes(),
            attribute => attribute.Name.LocalName == "Command"
                && attribute.Value == $"{{Binding {commandName}}}");
    }

    [Fact]
    public void ComposerInputKeepsEveryInteractionBackgroundTransparent()
    {
        var view = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "Views",
            "ComposerWindow.xaml"));
        XElement input = Assert.Single(
            view.Descendants(),
            element => element.Name.LocalName == "TextBox"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == "MessageInput"));

        Assert.Equal("Transparent", input.Attribute("Background")?.Value);
        string[] backgroundKeys = [.. input
            .Descendants()
            .Where(element => element.Name.LocalName == "SolidColorBrush")
            .Where(element => element.Attribute("Color")?.Value == "Transparent")
            .Select(element => element.Attributes().Single(attribute =>
                attribute.Name.LocalName == "Key").Value)];

        Assert.Equal(
            [
                "TextControlBackground",
                "TextControlBackgroundPointerOver",
                "TextControlBackgroundFocused",
                "TextControlBackgroundDisabled",
            ],
            backgroundKeys);
    }

    [Fact]
    public void ComposerUsesOneFullWindowBackgroundSurface()
    {
        var view = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "Views",
            "ComposerWindow.xaml"));
        XElement root = Assert.Single(
            view.Root!.Elements(),
            element => element.Name.LocalName == "Grid"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == "ComposerRoot"));
        XElement inset = Assert.Single(
            root.Elements(),
            element => element.Name.LocalName == "Border");

        Assert.Equal(
            "{ThemeResource SideyComposerBackgroundBrush}",
            root.Attribute("Background")?.Value);
        Assert.DoesNotContain(
            root.Elements(),
            element => element.Name.LocalName == "Grid.Resources");
        Assert.Equal("Transparent", inset.Attribute("Background")?.Value);
        Assert.Null(inset.Attribute("Margin"));
        Assert.Equal("14,10", inset.Attribute("Padding")?.Value);
    }

    [Fact]
    public void ComposerSurfaceDefinesLightDarkAndHighContrastThemeBrushes()
    {
        var app = XDocument.Load(RepositoryPath(
            "windows",
            "src",
            "Sidey.App",
            "App.xaml"));
        XElement themeDictionaries = Assert.Single(
            app.Descendants(),
            element => element.Name.LocalName == "ResourceDictionary.ThemeDictionaries");
        var dictionaries = themeDictionaries
            .Elements()
            .ToDictionary(
                element => element.Attributes().Single(attribute => attribute.Name.LocalName == "Key").Value,
                element => element);

        Assert.Equal(["Default", "HighContrast", "Light"], dictionaries.Keys.Order(StringComparer.Ordinal));
        AssertComposerAcrylic(dictionaries["Default"], "#2C2C2C");
        AssertComposerAcrylic(dictionaries["Light"], "#F9F9F9");

        XElement highContrast = Assert.Single(
            dictionaries["HighContrast"].Elements(),
            element => element.Name.LocalName == "SolidColorBrush"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Key"
                    && attribute.Value == "SideyComposerBackgroundBrush"));
        Assert.Equal("{ThemeResource SystemColorWindowColor}", highContrast.Attribute("Color")?.Value);
    }

    [Fact]
    public void StoreProductButtonStretchesAcrossItsUniformGridCell()
    {
        XDocument view = MainWindowView();
        XElement repeater = Assert.Single(
            view.Descendants(),
            element => element.Name.LocalName == "ItemsRepeater"
                && element.Attribute("ItemsSource")?.Value == "{Binding VisibleStoreProducts}");
        XElement button = Assert.Single(
            repeater.Descendants(),
            element => element.Name.LocalName == "Button"
                && element.Attribute("Command")?.Value == "{Binding PreviewCommand}");

        Assert.Equal("204", button.Attribute("MinHeight")?.Value);
        Assert.Equal("Stretch", button.Attribute("HorizontalAlignment")?.Value);
        Assert.Equal("Stretch", button.Attribute("VerticalAlignment")?.Value);
        Assert.Equal("Stretch", button.Attribute("HorizontalContentAlignment")?.Value);
        Assert.Equal("Stretch", button.Attribute("VerticalContentAlignment")?.Value);
    }

    [Fact]
    public void GroupHeaderDefinesAFullWidthPointerOverSurface()
    {
        XDocument view = MainWindowView();
        XElement header = Assert.Single(
            view.Descendants(),
            element => element.Name.LocalName == "Grid"
                && element.Attribute("Tapped")?.Value == "OnRoomHeaderTapped");
        XElement hoverSurface = Assert.Single(
            header.Elements(),
            element => element.Name.LocalName == "Border"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == "RoomHeaderHoverBackground"));

        Assert.Equal("OnRoomHeaderPointerEntered", header.Attribute("PointerEntered")?.Value);
        Assert.Equal("OnRoomHeaderPointerExited", header.Attribute("PointerExited")?.Value);
        Assert.Equal("3", hoverSurface.Attribute("Grid.ColumnSpan")?.Value);
        Assert.Equal("False", hoverSurface.Attribute("IsHitTestVisible")?.Value);
        Assert.Equal("-20", hoverSurface.Attribute("Margin")?.Value);
        Assert.Equal("8", hoverSurface.Attribute("CornerRadius")?.Value);
        Assert.Equal("0", hoverSurface.Attribute("Opacity")?.Value);
    }

    [Fact]
    public void GroupsPageUsesTheViewportWidthBeforeCenteringItsContent()
    {
        XDocument view = MainWindowView();
        XElement page = Assert.Single(
            view.Descendants(),
            element => element.Name.LocalName == "ScrollViewer"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == "GroupsPage"));
        XElement viewportHost = Assert.Single(
            page.Elements(),
            element => element.Name.LocalName == "Grid"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == "GroupsPageViewportHost"));
        XElement content = Assert.Single(viewportHost.Elements());

        Assert.Equal("StackPanel", content.Name.LocalName);
        Assert.Equal("32,24", content.Attribute("Padding")?.Value);
        Assert.Equal("820", content.Attribute("MaxWidth")?.Value);
        Assert.Equal("Stretch", content.Attribute("HorizontalAlignment")?.Value);
    }

    [Fact]
    public void InformationPageExposesAnUpdateSectionScrollTarget()
    {
        XDocument view = MainWindowView();
        XElement updateSection = Assert.Single(
            view.Descendants(),
            element => element.Attributes().Any(attribute =>
                attribute.Name.LocalName == "Name"
                && attribute.Value == "UpdateSection"));

        Assert.Contains(
            updateSection.Descendants(),
            element => element.Attribute("Text")?.Value
                == "{Binding Value, Source={i18n:I18n Key=settings.updateTitle}, Mode=OneWay}");
    }

    [Theory]
    [InlineData("HomePage")]
    [InlineData("GroupsPage")]
    [InlineData("StorePage")]
    [InlineData("SettingsPage")]
    [InlineData("AboutPage")]
    public void PageScrollbarUsesTheFullNavigationContentWidth(string pageName)
    {
        XDocument view = MainWindowView();
        XElement page = Assert.Single(
            view.Descendants(),
            element => element.Name.LocalName == "ScrollViewer"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Name"
                    && attribute.Value == pageName));
        XElement content = Assert.Single(
            page.Descendants(),
            element => element.Attribute("Padding")?.Value == "32,24"
                && element.Attribute("MaxWidth")?.Value == "820");

        Assert.Equal("Stretch", page.Attribute("HorizontalContentAlignment")?.Value);
        Assert.Equal("Disabled", page.Attribute("HorizontalScrollMode")?.Value);
        Assert.Equal("Disabled", page.Attribute("HorizontalScrollBarVisibility")?.Value);
        Assert.Equal("32,24", content.Attribute("Padding")?.Value);
        Assert.Equal("820", content.Attribute("MaxWidth")?.Value);
        Assert.Equal("Stretch", content.Attribute("HorizontalAlignment")?.Value);
        Assert.Null(page.Parent?.Attribute("Padding"));
        Assert.Null(page.Parent?.Attribute("MaxWidth"));
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
        && s_forbiddenAssemblyPrefixes.Any(prefix => name.StartsWith(prefix, StringComparison.Ordinal));

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

    private static XDocument MainWindowView() => XDocument.Load(RepositoryPath(
        "windows",
        "src",
        "Sidey.App",
        "Views",
        "MainWindow.xaml"));

    private static void AssertComposerAcrylic(XElement dictionary, string expectedColor)
    {
        XElement brush = Assert.Single(
            dictionary.Elements(),
            element => element.Name.LocalName == "AcrylicBrush"
                && element.Attributes().Any(attribute =>
                    attribute.Name.LocalName == "Key"
                    && attribute.Value == "SideyComposerBackgroundBrush"));

        Assert.Equal(expectedColor, brush.Attribute("FallbackColor")?.Value);
        Assert.Equal(expectedColor, brush.Attribute("TintColor")?.Value);
        Assert.Equal("0.96", brush.Attribute("TintLuminosityOpacity")?.Value);
        Assert.Equal("0.15", brush.Attribute("TintOpacity")?.Value);
    }
}
