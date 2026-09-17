using System.Windows.Input;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Sidey.Core.Domain;
using Windows.System;
using Windows.UI.Core;

namespace Sidey.App.Controls;

/// <summary>
/// A button that reports one key combination while its settings row is recording.
/// It reads keys only while it has keyboard focus inside SIDEY.
/// </summary>
public sealed partial class ShortcutRecorder : Button
{
    public static readonly DependencyProperty IsRecordingProperty = DependencyProperty.Register(
        nameof(IsRecording),
        typeof(bool),
        typeof(ShortcutRecorder),
        new PropertyMetadata(false, OnIsRecordingChanged));

    public static readonly DependencyProperty RecordCommandProperty = DependencyProperty.Register(
        nameof(RecordCommand),
        typeof(ICommand),
        typeof(ShortcutRecorder),
        new PropertyMetadata(null));

    public static readonly DependencyProperty CancelCommandProperty = DependencyProperty.Register(
        nameof(CancelCommand),
        typeof(ICommand),
        typeof(ShortcutRecorder),
        new PropertyMetadata(null));

    private VirtualKey? _suppressedKeyUp;

    public ShortcutRecorder()
    {
        DefaultStyleKey = typeof(Button);
        LostFocus += (_, _) => CancelRecording();
        Unloaded += (_, _) => CancelRecording();
    }

    public bool IsRecording
    {
        get => (bool)GetValue(IsRecordingProperty);
        set => SetValue(IsRecordingProperty, value);
    }

    public ICommand? RecordCommand
    {
        get => (ICommand?)GetValue(RecordCommandProperty);
        set => SetValue(RecordCommandProperty, value);
    }

    public ICommand? CancelCommand
    {
        get => (ICommand?)GetValue(CancelCommandProperty);
        set => SetValue(CancelCommandProperty, value);
    }

    protected override void OnPreviewKeyDown(KeyRoutedEventArgs e)
    {
        if (!IsRecording)
        {
            base.OnPreviewKeyDown(e);
            return;
        }

        // Keep Space and Enter from clicking the button again while recording.
        e.Handled = true;
        if (e.KeyStatus.WasKeyDown || IsModifierKey(e.Key))
        {
            return;
        }

        _suppressedKeyUp = e.Key;
        if (e.Key == VirtualKey.Escape)
        {
            CancelRecording();
            return;
        }

        var shortcut = new GlobalShortcut(CurrentModifiers(), (int)e.Key);
        if (RecordCommand?.CanExecute(shortcut) == true)
        {
            RecordCommand.Execute(shortcut);
        }
    }

    protected override void OnPreviewKeyUp(KeyRoutedEventArgs e)
    {
        if (!IsRecording && e.Key != _suppressedKeyUp)
        {
            base.OnPreviewKeyUp(e);
            return;
        }

        e.Handled = true;
        if (e.Key == _suppressedKeyUp)
        {
            _suppressedKeyUp = null;
        }
    }

    private static void OnIsRecordingChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        if (sender is ShortcutRecorder recorder && args.NewValue is true)
        {
            recorder.Focus(FocusState.Programmatic);
        }
    }

    private void CancelRecording()
    {
        if (IsRecording && CancelCommand?.CanExecute(null) == true)
        {
            CancelCommand.Execute(null);
        }
    }

    private static bool IsModifierKey(VirtualKey key) => key is VirtualKey.Control
        or VirtualKey.LeftControl
        or VirtualKey.RightControl
        or VirtualKey.Menu
        or VirtualKey.LeftMenu
        or VirtualKey.RightMenu
        or VirtualKey.Shift
        or VirtualKey.LeftShift
        or VirtualKey.RightShift
        or VirtualKey.LeftWindows
        or VirtualKey.RightWindows;

    private static GlobalShortcutModifiers CurrentModifiers()
    {
        GlobalShortcutModifiers modifiers = GlobalShortcutModifiers.None;
        if (IsDown(VirtualKey.Control))
        {
            modifiers |= GlobalShortcutModifiers.Control;
        }
        if (IsDown(VirtualKey.Menu))
        {
            modifiers |= GlobalShortcutModifiers.Alt;
        }
        if (IsDown(VirtualKey.Shift))
        {
            modifiers |= GlobalShortcutModifiers.Shift;
        }
        if (IsDown(VirtualKey.LeftWindows) || IsDown(VirtualKey.RightWindows))
        {
            modifiers |= GlobalShortcutModifiers.Windows;
        }
        return modifiers;
    }

    private static bool IsDown(VirtualKey key) =>
        (InputKeyboardSource.GetKeyStateForCurrentThread(key) & CoreVirtualKeyStates.Down) != 0;
}
