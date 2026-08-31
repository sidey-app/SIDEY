using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Sidey.Core.Domain;
using Windows.System;
using Windows.UI.Core;

namespace Sidey.App;

public sealed partial class ComposerWindow : Window
{
    private const int ComposerWidth = 400;
    private const int ComposerHeight = 56;

    public ComposerWindow()
    {
        InitializeComponent();
        Title = "SIDEY 메시지";
        ExtendsContentIntoTitleBar = true;
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsResizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }
    }

    public event Action<string>? SendRequested;

    public void ShowAndFocus()
    {
        Activate();
        ResizeAndCenter();
        MessageInput.Focus(FocusState.Programmatic);
    }

    public void HideComposer()
    {
        AppWindow.Hide();
    }

    private void OnMessageInputKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            HideComposer();
            return;
        }

        if (args.Key != VirtualKey.Enter)
        {
            return;
        }

        var shiftState = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift);
        if ((shiftState & CoreVirtualKeyStates.Down) != 0)
        {
            if (MessageInput.Text.Count(character => character == '\n') + 1
                >= MessageValidator.MaximumLines)
            {
                args.Handled = true;
            }

            return;
        }

        args.Handled = true;
        var body = MessageValidator.Normalize(MessageInput.Text);
        if (!MessageValidator.IsValid(body))
        {
            MessageInput.PlaceholderText = "1~200자, 최대 3줄까지만 보낼 수 있음";
            return;
        }

        SendRequested?.Invoke(body);
        MessageInput.Text = string.Empty;
        HideComposer();
    }

    private void ResizeAndCenter()
    {
        var scale = ComposerRoot.XamlRoot?.RasterizationScale ?? 1d;
        var width = (int)Math.Round(ComposerWidth * scale, MidpointRounding.AwayFromZero);
        var height = (int)Math.Round(ComposerHeight * scale, MidpointRounding.AwayFromZero);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(width, height));

        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            workArea.X + ((workArea.Width - width) / 2),
            workArea.Y + workArea.Height - height - (int)Math.Round(80 * scale)));
    }
}
