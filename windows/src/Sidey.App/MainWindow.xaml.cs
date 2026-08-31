using Microsoft.UI.Xaml;

namespace Sidey.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "SIDEY";
    }

    public void SetSliceReady()
    {
        StatusInfoBar.Severity = InfoBarSeverity.Success;
        StatusInfoBar.Message = "로컬 햄스터 오버레이가 실행 중. 햄스터를 누르면 입력창이 열림.";
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
}
