using System.Diagnostics;

namespace FPSBaseLauncher;

// Source-pull launcher. Clone or `git pull` the repo into ./source,
// then run Godot pointing at the project. GDScript only — no dotnet build.
//
// Required on host:
//   - git on PATH
//   - Godot 4.6.x — set FPSBASE_GODOT_EXE or put on PATH.
internal static class Program
{
    private const string RepoUrl = "https://github.com/strawberry-cow38/Evil-Game.git";
    private const string SourceDirName = "source";

    private static int Main()
    {
        Console.Title = "FPS Base — Launcher";
        try
        {
            var baseDir = AppContext.BaseDirectory;
            var srcDir = Path.Combine(baseDir, SourceDirName);

            var git = ResolveOnPath("git");
            if (git is null) return Bail("git not found on PATH.");

            var godot = ResolveGodot();
            if (godot is null) return Bail("Godot exe not found. Set FPSBASE_GODOT_EXE or put it on PATH.");

            if (!Directory.Exists(Path.Combine(srcDir, ".git")))
            {
                Console.WriteLine($"Cloning {RepoUrl} → {srcDir}");
                if (Run(git, new[] { "clone", "--depth", "1", RepoUrl, srcDir }, baseDir) != 0)
                {
                    return Bail("git clone failed.");
                }
            }
            else
            {
                Console.WriteLine($"git pull in {srcDir}");
                if (Run(git, new[] { "pull", "--ff-only" }, srcDir) != 0)
                {
                    return Bail("git pull failed (uncommitted changes? non-fast-forward?).");
                }
            }

            Console.WriteLine($"Launching Godot: {godot}");
            var psi = new ProcessStartInfo(godot)
            {
                UseShellExecute = false,
                WorkingDirectory = srcDir,
            };
            psi.ArgumentList.Add("--path");
            psi.ArgumentList.Add(srcDir);
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Launcher error:");
            Console.Error.WriteLine(ex);
            return Bail(null);
        }
    }

    private static int Run(string exe, string[] args, string workingDir)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            WorkingDirectory = workingDir,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        p.WaitForExit();
        return p.ExitCode;
    }

    private static string? ResolveOnPath(string tool)
    {
        var pathExt = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT;.COM")
            .Split(';', StringSplitOptions.RemoveEmptyEntries);
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        foreach (var dir in paths)
        {
            foreach (var ext in pathExt)
            {
                var candidate = Path.Combine(dir, tool + ext);
                if (File.Exists(candidate)) return candidate;
            }
            var bare = Path.Combine(dir, tool);
            if (File.Exists(bare)) return bare;
        }
        return null;
    }

    private static string? ResolveGodot()
    {
        var env = Environment.GetEnvironmentVariable("FPSBASE_GODOT_EXE");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;

        foreach (var name in new[] { "godot", "Godot", "godot_mono", "Godot_mono" })
        {
            var hit = ResolveOnPath(name);
            if (hit is not null) return hit;
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var roots = new[]
        {
            Path.Combine(localAppData, "Godot"),
            Path.Combine(programFiles, "Godot"),
            @"C:\Godot",
            @"C:\Program Files\Godot",
        };
        foreach (var root in roots)
        {
            if (!Directory.Exists(root)) continue;
            var hit = Directory
                .EnumerateFiles(root, "Godot_v*_win64.exe", SearchOption.AllDirectories)
                .Where(p => !p.Contains("_console", StringComparison.OrdinalIgnoreCase))
                .FirstOrDefault();
            if (hit is not null) return hit;
        }
        return null;
    }

    private static int Bail(string? reason)
    {
        if (reason is not null)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine(reason);
        }
        Console.WriteLine();
        Console.WriteLine("Press any key to close...");
        try { Console.ReadKey(intercept: true); } catch { }
        return 1;
    }
}
