using System.IO;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class SettingsStoreRecoveryTests
{
    [Fact]
    public async Task CorruptSettings_AreQuarantinedBeforeDefaultsAreSaved()
    {
        var directory = Directory.CreateTempSubdirectory("claudeusage-settings-recovery-");
        try
        {
            var settingsPath = Path.Combine(directory.FullName, "settings.json");
            var originalBytes = "{ this is not valid settings JSON"u8.ToArray();
            await File.WriteAllBytesAsync(settingsPath, originalBytes);
            var timestamp = new DateTimeOffset(
                2026, 7, 13, 5, 12, 34, TimeSpan.Zero);

            var recovered = SettingsStore.Load(settingsPath, timestamp);

            Assert.Equal(AppSettings.CurrentSchemaVersion, recovered.SchemaVersion);
            Assert.False(File.Exists(settingsPath));
            var quarantinePath = Assert.Single(
                Directory.GetFiles(directory.FullName, "settings.corrupt-*.json"));
            Assert.Equal(originalBytes, await File.ReadAllBytesAsync(quarantinePath));

            recovered.StartWithWindows = true;
            Assert.True(SettingsStore.Save(recovered, settingsPath, timestamp));
            Assert.True(File.Exists(settingsPath));
            Assert.True(SettingsStore.Load(settingsPath, timestamp).StartWithWindows);
            Assert.Equal(
                quarantinePath,
                Assert.Single(Directory.GetFiles(directory.FullName, "settings.corrupt-*.json")));
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task QuarantineFailure_PreventsOverwriteUntilOriginalCanBePreserved()
    {
        var directory = Directory.CreateTempSubdirectory("claudeusage-settings-locked-");
        try
        {
            var settingsPath = Path.Combine(directory.FullName, "settings.json");
            var originalBytes = "invalid-json"u8.ToArray();
            await File.WriteAllBytesAsync(settingsPath, originalBytes);
            var timestamp = new DateTimeOffset(
                2026, 7, 13, 6, 0, 0, TimeSpan.Zero);
            AppSettings recovered;

            using (new FileStream(
                       settingsPath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read))
            {
                recovered = SettingsStore.Load(settingsPath, timestamp);

                Assert.False(SettingsStore.Save(recovered, settingsPath, timestamp));
                Assert.Equal(originalBytes, await File.ReadAllBytesAsync(settingsPath));
                Assert.Empty(Directory.GetFiles(directory.FullName, "settings.corrupt-*.json"));
            }

            Assert.True(SettingsStore.Save(
                recovered,
                settingsPath,
                timestamp.AddSeconds(1)));
            Assert.True(File.Exists(settingsPath));
            var quarantinePath = Assert.Single(
                Directory.GetFiles(directory.FullName, "settings.corrupt-*.json"));
            Assert.Equal(originalBytes, await File.ReadAllBytesAsync(quarantinePath));
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task ValidSettings_AreLoadedWithoutCreatingAQuarantineCopy()
    {
        var directory = Directory.CreateTempSubdirectory("claudeusage-settings-valid-");
        try
        {
            var settingsPath = Path.Combine(directory.FullName, "settings.json");
            await File.WriteAllTextAsync(
                settingsPath,
                """
                {
                  "startWithWindows": true
                }
                """);

            var settings = SettingsStore.Load(
                settingsPath,
                DateTimeOffset.UnixEpoch);

            Assert.True(settings.StartWithWindows);
            Assert.True(File.Exists(settingsPath));
            Assert.Empty(Directory.GetFiles(directory.FullName, "settings.corrupt-*.json"));
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }
}
