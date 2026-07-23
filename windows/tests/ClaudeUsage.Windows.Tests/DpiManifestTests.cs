using System.IO;
using System.Xml.Linq;
using System.Runtime.InteropServices;
using System.Text;

namespace ClaudeUsage.Windows.Tests;

public sealed class DpiManifestTests
{
    [Fact]
    public void ExecutableManifestDeclaresPerMonitorV2WithFallback()
    {
        var manifestPath = FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "app.manifest");
        var document = XDocument.Load(manifestPath);
        XNamespace dpi2005 = "http://schemas.microsoft.com/SMI/2005/WindowsSettings";
        XNamespace dpi2016 = "http://schemas.microsoft.com/SMI/2016/WindowsSettings";

        Assert.Equal("true/pm", document.Descendants(dpi2005 + "dpiAware").Single().Value);
        Assert.Equal(
            "PerMonitorV2, PerMonitor",
            document.Descendants(dpi2016 + "dpiAwareness").Single().Value);
    }

    [Fact]
    public void BuiltExecutableEmbedsPerMonitorV2Manifest()
    {
        var executablePath = Path.Combine(AppContext.BaseDirectory, "ClaudeUsage.Windows.exe");
        Assert.True(File.Exists(executablePath), $"Missing test apphost: {executablePath}");

        var manifest = ReadEmbeddedManifest(executablePath);

        Assert.Contains("<dpiAware", manifest, StringComparison.Ordinal);
        Assert.Contains(">true/pm</dpiAware>", manifest, StringComparison.Ordinal);
        Assert.Contains("<dpiAwareness", manifest, StringComparison.Ordinal);
        Assert.Contains(">PerMonitorV2, PerMonitor</dpiAwareness>", manifest, StringComparison.Ordinal);
    }

    private static string FindRepositoryFile(params string[] segments)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine([directory.FullName, .. segments]);
            if (File.Exists(candidate))
            {
                return candidate;
            }
            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Could not locate {Path.Combine(segments)}.");
    }

    private static string ReadEmbeddedManifest(string executablePath)
    {
        const uint loadLibraryAsDataFile = 0x00000002;
        var module = LoadLibraryEx(executablePath, IntPtr.Zero, loadLibraryAsDataFile);
        if (module == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            var resource = FindResource(module, new IntPtr(1), new IntPtr(24));
            Assert.NotEqual(IntPtr.Zero, resource);
            var size = SizeofResource(module, resource);
            Assert.InRange(size, 1u, 1024u * 1024u);
            var loadedResource = LoadResource(module, resource);
            Assert.NotEqual(IntPtr.Zero, loadedResource);
            var bytesPointer = LockResource(loadedResource);
            Assert.NotEqual(IntPtr.Zero, bytesPointer);
            var bytes = new byte[size];
            Marshal.Copy(bytesPointer, bytes, 0, checked((int)size));

            if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
            {
                return Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2).TrimEnd('\0');
            }
            if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            {
                return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3).TrimEnd('\0');
            }
            return Encoding.UTF8.GetString(bytes).TrimEnd('\0');
        }
        finally
        {
            _ = FreeLibrary(module);
        }
    }

#pragma warning disable SYSLIB1054 // Tests read an integer-named Win32 resource; DllImport avoids unsafe source generation.
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(IntPtr module);
#pragma warning restore SYSLIB1054
}
