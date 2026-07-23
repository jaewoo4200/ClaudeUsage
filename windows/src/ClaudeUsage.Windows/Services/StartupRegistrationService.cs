using Microsoft.Win32;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Windows.ApplicationModel;

namespace ClaudeUsage.Windows.Services;

public sealed class StartupRegistrationService
{
    internal const string PackagedTaskId = "ClaudeUsageStartup";

    private readonly IStartupRegistrationBackend _activeBackend;
    private readonly IStartupRegistrationBackend? _legacyPortableBackend;
    private readonly bool _hasPackageIdentity;

    public StartupRegistrationService()
        : this(
            PackageIdentityDetector.HasPackageIdentity(),
            new PackagedStartupTaskRegistration(PackagedTaskId),
            new PortableRunKeyStartupRegistration(
                new CurrentUserRunKeyStore(),
                () => Environment.ProcessPath))
    {
    }

    internal StartupRegistrationService(
        bool hasPackageIdentity,
        IStartupRegistrationBackend packagedBackend,
        IStartupRegistrationBackend portableBackend)
    {
        ArgumentNullException.ThrowIfNull(packagedBackend);
        ArgumentNullException.ThrowIfNull(portableBackend);

        _hasPackageIdentity = hasPackageIdentity;
        _activeBackend = hasPackageIdentity ? packagedBackend : portableBackend;
        _legacyPortableBackend = hasPackageIdentity ? portableBackend : null;
    }

    public bool IsEnabled() => _activeBackend.IsEnabled();

    public void SetEnabled(bool enabled)
    {
        // Keep the portable registration until the package-identity task has
        // reached the requested state. If Windows rejects package registration,
        // the user's existing ZIP auto-start path remains usable.
        _activeBackend.SetEnabled(enabled);
        _legacyPortableBackend?.SetEnabled(false);
    }

    internal void SynchronizePackagedBeforeInstanceHandoff(bool enabled)
    {
        // A packaged process can be the secondary instance while a portable
        // process is still running. Migrate before handing off and exiting so the
        // next sign-in starts the package. Portable secondaries must be read-only.
        if (!_hasPackageIdentity)
        {
            return;
        }

        SetEnabled(enabled);
    }
}

internal interface IStartupRegistrationBackend
{
    bool IsEnabled();

    void SetEnabled(bool enabled);
}

internal sealed class PackagedStartupTaskRegistration(string taskId) : IStartupRegistrationBackend
{
    private readonly string _taskId = string.IsNullOrWhiteSpace(taskId)
        ? throw new ArgumentException("A startup task id is required.", nameof(taskId))
        : taskId;

    public bool IsEnabled()
    {
        try
        {
            var state = GetTask().State;
            return state is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
        }
        catch (Exception exception) when (exception is not InvalidOperationException)
        {
            throw new InvalidOperationException(
                "The packaged ClaudeUsage startup task could not be read.",
                exception);
        }
    }

    public void SetEnabled(bool enabled)
    {
        try
        {
            var task = GetTask();
            var state = task.State;
            if (!enabled)
            {
                if (state == StartupTaskState.EnabledByPolicy)
                {
                    throw new InvalidOperationException(
                        "Windows policy requires ClaudeUsage to run at sign-in.");
                }

                if (state == StartupTaskState.Enabled)
                {
                    task.Disable();
                }

                return;
            }

            if (state is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy)
            {
                return;
            }

            if (state == StartupTaskState.DisabledByUser)
            {
                throw new InvalidOperationException(
                    "Windows disabled ClaudeUsage in Startup Apps. Re-enable it in Windows Settings.");
            }

            if (state == StartupTaskState.DisabledByPolicy)
            {
                throw new InvalidOperationException(
                    "Windows policy prevents ClaudeUsage from running at sign-in.");
            }

            var result = task.RequestEnableAsync().AsTask().GetAwaiter().GetResult();
            if (result is not StartupTaskState.Enabled and not StartupTaskState.EnabledByPolicy)
            {
                throw new InvalidOperationException(
                    $"Windows did not enable the ClaudeUsage startup task (state: {result}).");
            }
        }
        catch (Exception exception) when (exception is not InvalidOperationException)
        {
            throw new InvalidOperationException(
                "The packaged ClaudeUsage startup task could not be changed.",
                exception);
        }
    }

    private StartupTask GetTask() =>
        StartupTask.GetAsync(_taskId).AsTask().GetAwaiter().GetResult();
}

internal sealed class PortableRunKeyStartupRegistration(
    IRunKeyStore runKeyStore,
    Func<string?> processPathProvider) : IStartupRegistrationBackend
{
    private readonly IRunKeyStore _runKeyStore =
        runKeyStore ?? throw new ArgumentNullException(nameof(runKeyStore));
    private readonly Func<string?> _processPathProvider =
        processPathProvider ?? throw new ArgumentNullException(nameof(processPathProvider));

    public bool IsEnabled() => !string.IsNullOrWhiteSpace(_runKeyStore.Read());

    public void SetEnabled(bool enabled)
    {
        if (!enabled)
        {
            _runKeyStore.Delete();
            return;
        }

        var executablePath = _processPathProvider();
        if (string.IsNullOrWhiteSpace(executablePath) || !File.Exists(executablePath))
        {
            throw new InvalidOperationException(
                "The current ClaudeUsage executable path could not be resolved.");
        }

        // Rewrite on every synchronization. This repairs an old portable path
        // after the user moves or replaces the extracted ZIP directory.
        _runKeyStore.Write($"\"{executablePath}\" --background");
    }
}

internal interface IRunKeyStore
{
    string? Read();

    void Write(string value);

    void Delete();
}

internal sealed class CurrentUserRunKeyStore : IRunKeyStore
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ClaudeUsage";

    public string? Read()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(ValueName) as string;
    }

    public void Write(string value)
    {
        using var key = OpenWritableKey();
        key.SetValue(ValueName, value, RegistryValueKind.String);
    }

    public void Delete()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
        key?.DeleteValue(ValueName, throwOnMissingValue: false);
    }

    private static RegistryKey OpenWritableKey() =>
        Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true)
        ?? throw new InvalidOperationException("Windows startup settings could not be opened.");
}

internal static partial class PackageIdentityDetector
{
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;

    public static bool HasPackageIdentity()
    {
        uint length = 0;
        var result = GetCurrentPackageFullName(ref length, IntPtr.Zero);
        return InterpretResult(result);
    }

    internal static bool InterpretResult(int result)
    {
        return result switch
        {
            0 or ErrorInsufficientBuffer => true,
            AppModelErrorNoPackage => false,
            _ => throw new Win32Exception(result, "Unable to determine package identity."),
        };
    }

    [LibraryImport("kernel32.dll")]
    private static partial int GetCurrentPackageFullName(
        ref uint packageFullNameLength,
        IntPtr packageFullName);
}
