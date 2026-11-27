using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Markup;

namespace Probe;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(p =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App();
        });
    }
}

public class App : Application
{
    static void Try(StreamWriter report, string label, Action body)
    {
        try
        {
            body();
            report.WriteLine($"{label}: succeeded");
        }
        catch (Exception e)
        {
            report.WriteLine($"{label}: {e.GetType().Name} HResult 0x{e.HResult:x8}: {e.Message}");
        }
        report.Flush();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        using var report = new StreamWriter(Environment.GetEnvironmentVariable("PROBE_OUT"));
        report.WriteLine($"process architecture {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}, os {System.Runtime.InteropServices.RuntimeInformation.OSArchitecture}");
        const string ns = "xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\"";
        Try(report, "new XamlControlsResources()", () => { _ = new Microsoft.UI.Xaml.Controls.XamlControlsResources(); });
        Try(report, "XamlReader.Load of a ResourceDictionary holding x:Double 0.96", () => { _ = XamlReader.Load($"<ResourceDictionary {ns}><x:Double x:Key=\"t\">0.96</x:Double></ResourceDictionary>"); });
        Try(report, "XamlReader.Load of a ResourceDictionary holding x:Double 0.5", () => { _ = XamlReader.Load($"<ResourceDictionary {ns}><x:Double x:Key=\"t\">0.5</x:Double></ResourceDictionary>"); });
        Try(report, "XamlReader.Load of a Border with Opacity 0.96", () => { _ = XamlReader.Load($"<Border {ns} Opacity=\"0.96\"/>"); });
        Try(report, "XamlReader.Load of a Border with a StaticResource Double in its own resources", () => { _ = XamlReader.Load($"<Border {ns} Opacity=\"{{StaticResource t}}\"><Border.Resources><x:Double x:Key=\"t\">0.96</x:Double></Border.Resources></Border>"); });
        report.Flush();
        Exit();
    }
}
