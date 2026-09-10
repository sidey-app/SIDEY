using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Sidey.App.Controls;

/// <summary>Uses Thumb completion as well as track/key release; Slider can consume pointer release internally.</summary>
public sealed class SoundVolumeSlider : Slider
{
    private readonly List<Thumb> _thumbs = [];
    private long _gesture;
    private bool _completionQueued;
    public event Action? AdjustmentCompleted;
    public event Action? AdjustmentCanceled;

    public SoundVolumeSlider()
    {
        DefaultStyleKey = typeof(Slider);
        AddHandler(PointerPressedEvent, new PointerEventHandler((_, _) => BeginAdjustment()), true);
        AddHandler(PointerReleasedEvent, new PointerEventHandler((_, _) => QueueCompletion()), true);
        AddHandler(PointerCanceledEvent, new PointerEventHandler((_, _) => CancelAdjustment()), true);
        AddHandler(KeyDownEvent, new KeyEventHandler((_, e) => { if (IsAdjustmentKey(e.Key)) BeginAdjustment(); }), true);
        AddHandler(KeyUpEvent, new KeyEventHandler((_, e) => { if (IsAdjustmentKey(e.Key)) QueueCompletion(); }), true);
        LostFocus += (_, _) => CancelAdjustment();
        Unloaded += (_, _) => CancelAdjustment();
    }

    protected override void OnApplyTemplate()
    {
        foreach (Thumb thumb in _thumbs)
            thumb.DragCompleted -= OnDragCompleted;
        _thumbs.Clear();
        base.OnApplyTemplate();
        foreach (string name in new[] { "HorizontalThumb", "VerticalThumb" })
            if (GetTemplateChild(name) is Thumb thumb)
            {
                thumb.DragCompleted += OnDragCompleted;
                _thumbs.Add(thumb);
            }
    }

    internal int CompletionThumbCount => _thumbs.Count;

    private void OnDragCompleted(object sender, DragCompletedEventArgs e)
    {
        if (e.Canceled)
            CancelAdjustment();
        else
            QueueCompletion();
    }

    private void BeginAdjustment()
    {
        _gesture++;
        _completionQueued = false;
    }

    private void CancelAdjustment()
    {
        BeginAdjustment();
        AdjustmentCanceled?.Invoke();
    }

    private void QueueCompletion()
    {
        if (_completionQueued)
            return;
        _completionQueued = true;
        long gesture = _gesture;
        // Let Slider finish its final Value update and coalesce Thumb + routed release.
        DispatcherQueue.TryEnqueue(() =>
        {
            if (gesture != _gesture)
                return;
            _completionQueued = false;
            AdjustmentCompleted?.Invoke();
        });
    }

    private static bool IsAdjustmentKey(VirtualKey key) => key is VirtualKey.Left or VirtualKey.Right
        or VirtualKey.Up or VirtualKey.Down or VirtualKey.PageUp or VirtualKey.PageDown or VirtualKey.Home or VirtualKey.End;
}
