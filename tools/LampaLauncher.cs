// Compatibility entry point for Lampa Desktop's fixed player-name list.
// The actual player and all configuration live in the parent mpv+ directory.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
internal static class LampaLauncher {
    private static string Quote(string value) {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            slashes = 0;
            result.Append(c);
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    [STAThread]
    public static int Main(string[] args) {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        if (!File.Exists(Path.Combine(root, "mpv+.exe"))) root = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar)).FullName;
        var command = new StringBuilder();
        foreach (string arg in args) { if (command.Length > 0) command.Append(' '); command.Append(Quote(arg)); }
        var start = new ProcessStartInfo(Path.Combine(root, "mpv+.exe"), command.ToString());
        start.UseShellExecute = false;
        start.WorkingDirectory = root;
        try { using (var child = Process.Start(start)) { child.WaitForExit(); return child.ExitCode; } }
        catch { return 1; }
    }
}
