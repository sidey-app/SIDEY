using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sidey.Core.Domain;

namespace Sidey.App;

public sealed partial class MainWindow : Window
{
    public event Action<OverlayRegionPreference>? PresetRequested;

    public MainWindow()
    {
        InitializeComponent();
        Title = "SIDEY";
    }

    public void SetSliceReady(OverlayRegionPreference preference)
    {
        StatusInfoBar.Severity = InfoBarSeverity.Success;
        StatusInfoBar.Message = $"{EdgeName(preference.Edge)} · {SpanName(preference.Span)} 실행 중. 햄스터를 누르면 입력창이 열림.";
    }

    public void SetMessageInputVerified()
    {
        StatusInfoBar.Severity = InfoBarSeverity.Success;
        StatusInfoBar.Message = "로컬 Enter 전송 동작 확인됨. 아직 서버로 보내지는 않음.";
    }

    public void SetSliceFailure(Exception exception)
    {
        StatusInfoBar.Severity = InfoBarSeverity.Error;
        StatusInfoBar.Message = $"오버레이 시작 실패: {exception.Message}";
    }

    private void OnApplyPresetClicked(object sender, RoutedEventArgs args)
    {
        var edge = (OverlayEdge)Math.Clamp(EdgeSelector.SelectedIndex, 0, 3);
        var span = (OverlaySpan)Math.Clamp(SpanSelector.SelectedIndex, 0, 2);
        PresetRequested?.Invoke(new OverlayRegionPreference(edge, span, null));
    }

    private static string EdgeName(OverlayEdge edge) => edge switch
    {
        OverlayEdge.Bottom => "아래",
        OverlayEdge.Left => "왼쪽",
        OverlayEdge.Right => "오른쪽",
        OverlayEdge.Top => "위",
        _ => throw new ArgumentOutOfRangeException(nameof(edge)),
    };

    private static string SpanName(OverlaySpan span) => span switch
    {
        OverlaySpan.Third => "1/3",
        OverlaySpan.Half => "1/2",
        OverlaySpan.Full => "전체",
        _ => throw new ArgumentOutOfRangeException(nameof(span)),
    };
}
