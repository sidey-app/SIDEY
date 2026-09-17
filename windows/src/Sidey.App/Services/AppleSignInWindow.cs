using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Sidey.Infrastructure.Authentication;

namespace Sidey.App.Services;

/// <summary>Intercepts the exact registered HTTPS callback before any callback-host navigation.</summary>
internal static class AppleSignInWindow
{
    public static async Task<AppleIdentityProof> AuthenticateAsync(AppleDesktopOAuth request, CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<AppleIdentityProof>(TaskCreationOptions.RunContinuationsAsynchronously);
        var browser = new WebView2();
        var window = new Window { Title = "SIDEY — Apple", Content = browser };
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lifetime.CancelAfter(TimeSpan.FromMinutes(5));
        void Navigation(WebView2 sender, CoreWebView2NavigationStartingEventArgs args)
        {
            if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out Uri? uri))
            {
                args.Cancel = true;
                return;
            }
            if (request.IsCallback(uri))
            {
                args.Cancel = true;
                try
                { completion.TrySetResult(request.Complete(uri)); }
                catch (Exception error) { completion.TrySetException(error); }
                return;
            }
            // Authentication never navigates to non-Apple pages or executes a custom protocol.
            if (uri.Scheme != "https" || !(uri.IdnHost == "apple.com"
                || uri.IdnHost.EndsWith(".apple.com", StringComparison.Ordinal)))
                args.Cancel = true;
        }
        void Closed(object sender, WindowEventArgs args) => completion.TrySetCanceled();
        void Popup(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs args) => args.Handled = true;
        browser.NavigationStarting += Navigation;
        window.Closed += Closed;
        try
        {
            window.Activate();
            string userData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SIDEY", "AppleAuth");
            CoreWebView2Environment environment = await CoreWebView2Environment.CreateWithOptionsAsync(null, userData, null)
                .AsTask().WaitAsync(lifetime.Token);
            CoreWebView2ControllerOptions options = environment.CreateCoreWebView2ControllerOptions();
            options.IsInPrivateModeEnabled = true;
            await browser.EnsureCoreWebView2Async(environment, options).AsTask().WaitAsync(lifetime.Token);
            browser.CoreWebView2.Settings.AreDevToolsEnabled = false;
            browser.CoreWebView2.Settings.IsPasswordAutosaveEnabled = false;
            browser.CoreWebView2.NewWindowRequested += Popup;
            browser.Source = request.AuthorizationUri;
            return await completion.Task.WaitAsync(lifetime.Token);
        }
        finally
        {
            browser.NavigationStarting -= Navigation;
            window.Closed -= Closed;
            if (browser.CoreWebView2 is { } core)
                core.NewWindowRequested -= Popup;
            browser.Close();
            window.Close();
        }
    }
}
