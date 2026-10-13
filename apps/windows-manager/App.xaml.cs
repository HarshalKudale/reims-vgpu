using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace ReimsManager;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try {
            if (e.Args.Length >= 2 && e.Args[0] == "--echo-args") {
                File.WriteAllText(e.Args[1], JsonSerializer.Serialize(e.Args.Skip(2))); Shutdown(0); return;
            }
            if (e.Args.Length==2 && e.Args[0]=="--keyboard-probe") {
                var probe=new KeyboardProbe(Path.GetFullPath(e.Args[1])); MainWindow=probe; probe.Show(); return;
            }
            var window = new MainWindow(e.Args.Length==2 && e.Args[0]=="--self-test"); MainWindow = window;
            if (e.Args.Length == 2 && e.Args[0] == "--root") window.Root.Text = Path.GetFullPath(e.Args[1]);
            if (e.Args.Length == 2 && e.Args[0] == "--self-test") {
                string folder = Path.GetFullPath(e.Args[1]); Directory.CreateDirectory(folder);
                string[] values = ["", "日本語 path", "quote\"value", "trailing\\", "$(do-nothing)&literal", "comma,path"];
                string output = Path.Combine(folder, "argv.json");
                var info = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute=false, CreateNoWindow=true };
                foreach (string arg in new[] {"--echo-args",output}.Concat(values)) info.ArgumentList.Add(arg);
                using var child = Process.Start(info)!; await child.WaitForExitAsync();
                if (child.ExitCode != 0 || !values.SequenceEqual(JsonSerializer.Deserialize<string[]>(File.ReadAllText(output))!)) throw new Exception("Argument roundtrip failed");
                window.Opacity = 0; window.ShowInTaskbar = false; window.Show();
                await window.RenderChecks(folder);
                File.WriteAllText(Path.Combine(folder,"result.json"),"{\"fluent_theme\":true,\"argument_roundtrip\":true,\"pages_rendered\":12}");
                window.Close(); Shutdown(0); return;
            }
            window.Show();
        } catch (Exception error) {
            if (e.Args.Length > 0) {
                File.WriteAllText(Path.Combine(Path.GetFullPath(e.Args[^1]), "error.txt"), error.ToString()); Shutdown(1);
            } else { MessageBox.Show(error.Message,"Reims Manager"); Shutdown(1); }
        }
    }
}
