using ClaudeUsage.Windows.Services;
using System.ComponentModel;
using System.IO;

namespace ClaudeUsage.Windows.Tests;

public sealed class StartupRegistrationServiceTests
{
    [Theory]
    [InlineData(0, true)]
    [InlineData(122, true)]
    [InlineData(15700, false)]
    public void PackageIdentityResult_IsMappedWithoutReadingAnExecutablePath(
        int result,
        bool expected)
    {
        Assert.Equal(expected, PackageIdentityDetector.InterpretResult(result));
    }

    [Fact]
    public void PackageIdentityResult_RejectsUnexpectedNativeFailure()
    {
        Assert.Throws<Win32Exception>(() => PackageIdentityDetector.InterpretResult(5));
    }

    [Fact]
    public void PackagedRegistration_ClearsLegacyRunPathAndUsesIdentityTask()
    {
        var calls = new List<string>();
        var packaged = new RecordingBackend(calls, "packaged");
        var portable = new RecordingBackend(calls, "portable");
        var service = new StartupRegistrationService(
            hasPackageIdentity: true,
            packaged,
            portable);

        service.SetEnabled(true);

        Assert.Equal(
            ["packaged:true", "portable:false"],
            calls);
        Assert.True(packaged.IsEnabled());
        Assert.False(portable.IsEnabled());
    }

    [Fact]
    public void PackagedRegistration_FailedEnablePreservesLegacyRunPath()
    {
        var calls = new List<string>();
        var packaged = new ThrowingBackend(calls, "packaged");
        var portable = new RecordingBackend(calls, "portable", initiallyEnabled: true);
        var service = new StartupRegistrationService(
            hasPackageIdentity: true,
            packaged,
            portable);

        Assert.Throws<InvalidOperationException>(() => service.SetEnabled(true));

        Assert.Equal(["packaged:true"], calls);
        Assert.True(portable.IsEnabled());
    }

    [Fact]
    public void PackagedPreHandoff_MigratesBeforeSecondaryInstanceCanExit()
    {
        var calls = new List<string>();
        var packaged = new RecordingBackend(calls, "packaged");
        var portable = new RecordingBackend(calls, "portable", initiallyEnabled: true);
        var service = new StartupRegistrationService(
            hasPackageIdentity: true,
            packaged,
            portable);

        service.SynchronizePackagedBeforeInstanceHandoff(enabled: true);

        Assert.Equal(["packaged:true", "portable:false"], calls);
        Assert.True(packaged.IsEnabled());
        Assert.False(portable.IsEnabled());
    }

    [Fact]
    public void PortablePreHandoff_HasNoRegistrationSideEffects()
    {
        var calls = new List<string>();
        var packaged = new RecordingBackend(calls, "packaged");
        var portable = new RecordingBackend(calls, "portable", initiallyEnabled: true);
        var service = new StartupRegistrationService(
            hasPackageIdentity: false,
            packaged,
            portable);

        service.SynchronizePackagedBeforeInstanceHandoff(enabled: true);

        Assert.Empty(calls);
        Assert.True(portable.IsEnabled());
    }

    [Fact]
    public void PortableRegistration_RewritesMovedExecutablePath()
    {
        var temporaryDirectory = Directory.CreateTempSubdirectory("claudeusage-startup-");
        try
        {
            var currentExecutable = Path.Combine(temporaryDirectory.FullName, "ClaudeUsage.Windows.exe");
            File.WriteAllBytes(currentExecutable, []);
            var store = new MemoryRunKeyStore
            {
                Value = "\"C:\\Program Files\\WindowsApps\\ClaudeUsage_0.1.0.0\\ClaudeUsage.Windows.exe\" --background",
            };
            var registration = new PortableRunKeyStartupRegistration(store, () => currentExecutable);

            registration.SetEnabled(true);

            Assert.Equal($"\"{currentExecutable}\" --background", store.Value);
        }
        finally
        {
            temporaryDirectory.Delete(recursive: true);
        }
    }

    [Fact]
    public void PackagedRegistration_AfterUpdateDoesNotReadVersionedExecutablePath()
    {
        var versionedPathWasRead = false;
        var legacyStore = new MemoryRunKeyStore
        {
            Value = "\"C:\\Program Files\\WindowsApps\\ClaudeUsage_0.1.0.0\\ClaudeUsage.Windows.exe\" --background",
        };
        var portable = new PortableRunKeyStartupRegistration(
            legacyStore,
            () =>
            {
                versionedPathWasRead = true;
                return @"C:\Program Files\WindowsApps\ClaudeUsage_0.2.0.0\ClaudeUsage.Windows.exe";
            });
        var packaged = new RecordingBackend([], "packaged");
        var service = new StartupRegistrationService(
            hasPackageIdentity: true,
            packaged,
            portable);

        service.SetEnabled(true);

        Assert.True(packaged.IsEnabled());
        Assert.Null(legacyStore.Value);
        Assert.False(versionedPathWasRead);
    }

    [Fact]
    public void PortableRegistration_DisableDoesNotResolveProcessPath()
    {
        var pathWasRead = false;
        var store = new MemoryRunKeyStore { Value = "old value" };
        var registration = new PortableRunKeyStartupRegistration(
            store,
            () =>
            {
                pathWasRead = true;
                return null;
            });

        registration.SetEnabled(false);

        Assert.Null(store.Value);
        Assert.False(pathWasRead);
    }

    private sealed class RecordingBackend(
        List<string> calls,
        string name,
        bool initiallyEnabled = false)
        : IStartupRegistrationBackend
    {
        private bool _enabled = initiallyEnabled;

        public bool IsEnabled() => _enabled;

        public void SetEnabled(bool enabled)
        {
            calls.Add($"{name}:{enabled.ToString().ToLowerInvariant()}");
            _enabled = enabled;
        }
    }

    private sealed class ThrowingBackend(List<string> calls, string name)
        : IStartupRegistrationBackend
    {
        public bool IsEnabled() => false;

        public void SetEnabled(bool enabled)
        {
            calls.Add($"{name}:{enabled.ToString().ToLowerInvariant()}");
            throw new InvalidOperationException("Registration failed.");
        }
    }

    private sealed class MemoryRunKeyStore : IRunKeyStore
    {
        public string? Value { get; set; }

        public string? Read() => Value;

        public void Write(string value) => Value = value;

        public void Delete() => Value = null;
    }
}
