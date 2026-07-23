# Windows 11 x64 clean-machine release smoke

Run this checklist on a disposable, fully updated Windows 11 x64 VM using a
standard (non-administrator) user. Take a clean snapshot first. Record the OS
build, WebView2 version, package hashes, certificate chain, and every result in
the release record. A publicly trusted production certificate needs no
elevation; a self-signed test certificate requires the temporary elevated
machine-store step described below.

## Preconditions

1. Obtain the signed base MSIX, signed upgrade MSIX, stable `.appinstaller`,
   SPDX SBOM, and `SHA256SUMS.txt` from the protected release-candidate run.
2. Verify all SHA-256 values with `Get-FileHash` and verify both MSIX signatures:

   ```powershell
   signtool verify /pa /all /v .\ClaudeUsage-Windows-<base>-win-x64.msix
   signtool verify /pa /all /v .\ClaudeUsage-Windows-<upgrade>-win-x64.msix
   ```

3. Confirm the signer chains to the intended trusted code-signing certificate,
   the timestamp is valid, and the manifest publisher exactly matches it.
4. Confirm Microsoft Edge WebView2 Evergreen Runtime is installed. Do not
   install a machine-wide .NET runtime; the package must be self-contained.
5. Install/sign in to official Codex only if exercising the live Codex path.
   Never place test credentials or provider auth files in build artifacts.

## Portable window movement gate

On the unlocked interactive desktop, open a **standard-user (not
administrator)** Windows PowerShell session. Do not use the mouse or keyboard
during this short gate: the runtime check performs real pointer drags on the
exact Settings, History, and Widget HWNDs and then restores the original cursor
position and foreground window.

Run the non-destructive Windows PowerShell 5.1 static check first, then test the
exact final ZIP submitted for release approval:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke.ps1 `
  -ZipPath .\ClaudeUsage-Windows-<version>-win-x64.zip
```

The runtime check safely extracts only under a unique bounded `%TEMP%`
directory, isolates the child process's `APPDATA`, `LOCALAPPDATA`, and `TEMP`,
and pins every tested window by exact PID, executable path, and title. It
requires a non-zero position delta, unchanged size, and a final rectangle
inside the monitor work area. Success also requires the real settings file's
existence/hash/length/mtime to remain unchanged, every exact test PID to stop,
and the bounded temporary directory to be absent. It does not install/remove
Appx packages, request UAC, or mutate certificates or the registry.

`-ExecutablePath .\portable\ClaudeUsage.Windows.exe` is available for local
unpacked-build diagnosis, but it does not replace the exact-ZIP release gate.

## Automated existing-user lifecycle check

The helper is an **existing-user lifecycle** check that installs only for the
current user. `%LOCALAPPDATA%\ClaudeUsage` may already exist and may contain
settings/history; it is not required to be empty. The helper refuses to proceed
if the tested package identity, a ClaudeUsage process, or the legacy `HKCU Run`
value already exists, so it cannot silently remove an existing installation.
It validates that each MSIX signature matches its manifest publisher, launches
the packaged app from its registered WindowsApps location, upgrades to a higher
version with the same identity, and relaunches from the upgraded versioned
location. It then removes the package and proves that a unique sentinel under
the existing state directory and pre-existing provider directories remain.

On every success or failure path, it attempts to stop all app processes created
by the run, remove every registration with the tested package identity, remove
the fake legacy Run value and test-only certificate, and remove only its unique
state sentinel. Final postconditions require those test-owned package/process/
registry/certificate remnants to be absent. Existing state contents are never
recursively deleted. A failure in cleanup is reported alongside the original
lifecycle failure instead of replacing it.

This helper does not replace the clean-machine release gate. Run it as one step
of this full checklist on the disposable VM described above, and complete the
manual product/update checks below.

The safety/structure check is non-destructive, uses the Windows PowerShell 5.1
parser, and can run on a developer machine; it never supplies the installation
acknowledgement:

```powershell
powershell.exe -NoProfile -File windows/scripts/test-msix-smoke-static.ps1
```

Open a **standard-user (not administrator)** PowerShell session for the
lifecycle run. The helper deliberately refuses to run the package lifecycle in
an elevated parent process:

```powershell
powershell.exe -NoProfile -File windows/scripts/test-msix-smoke.ps1 `
  -BaseMsixPath .\ClaudeUsage-Windows-<base>-win-x64.msix `
  -UpgradeMsixPath .\ClaudeUsage-Windows-<upgrade>-win-x64.msix `
  -PortableExecutablePath .\portable-base\ClaudeUsage.Windows.exe `
  -IUnderstandThisInstallsAndRemovesPackages
```

`-PortableExecutablePath` is optional but required for release approval. It
starts that owned ZIP build in the background, recreates a unique legacy Run
value after startup, and proves the packaged secondary migrates the value
before handing activation to the running ZIP instance and exiting.

For an internal test certificate only, export its public `.cer` and add
`-TestCertificatePath .\test-signing-public.cer` to that same **non-elevated**
command. Never run the full script as administrator. Windows validates MSIX
test certificates in the local machine's `TrustedPeople` store, so a narrowly
scoped Windows PowerShell lease broker requests UAC **once**. The standard-user
parent snapshots the public CER and broker source into a bounded immutable
`-EncodedCommand`, creates unique Ready/Complete/Finished/Failed named events
plus a parent-owned lease mutex, and starts that single elevated broker. Their
protected ACLs grant the standard-user parent full control and grant only
Synchronize/Modify to the built-in Administrators group and SYSTEM. This
permits an over-the-shoulder UAC approval with a different administrator
account without granting access to either user's process. The broker imports
the snapshot into
`LocalMachine\TrustedPeople`, signals Ready only after exact raw-data and
thumbprint verification, and remains alive as a watchdog. The standard-user
parent still performs every package, process, HKCU registry, launch, upgrade,
uninstall, and postcondition step.

The parent waits for Ready or an early Finished signal; it never opens, waits
on, or queries the elevated process. Normal parent cleanup signals Complete,
releases its lease mutex, waits for Finished, checks Failed, and then proves the
exact certificate is absent. The broker sets Failed for any operation or exact
cleanup error and sets Finished only as its final status signal. If the parent
thread or process is terminated after import, Windows abandons that
parent-owned mutex; the waiting broker detects the abandonment and performs
cleanup itself without opening the standard user's process. After Ready, a hard
15-minute parent-wait lease also reclaims trust when the parent hangs; it does
not claim to interrupt an OS certificate-store operation already in progress.
Deleting or changing the
original CER after UAC does not affect cleanup because the broker uses only its
in-memory snapshot. A global thumbprint mutex serializes two runs of this
harness, and both parent and broker refuse a matching trust entry that existed
before the test. Cancelling the sole UAC prompt occurs before import and leaves
no trust entry.

No user-mode `finally` block can survive termination of the broker itself,
forced logoff, OS crash, or power loss. Those events can leave the test
certificate trusted. On this disposable VM, revert the clean snapshot or first
confirm that the reported thumbprint and raw certificate bytes match the public
test certificate, then remove only that exact `LocalMachine\TrustedPeople`
entry from an administrator session. Never remove a certificate merely because
its display name looks similar. Production certificates should already chain
to a trusted root and must not use this option.

## Manual product and update checks

1. Install through the hosted `.appinstaller`, not only the raw MSIX. Confirm
   Windows shows the expected publisher and no unknown-publisher warning.
2. Launch from Start and the notification area, enable **Start with Windows**,
   and confirm `ClaudeUsage` appears once in Windows Startup Apps. Confirm the
   legacy `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value named
   `ClaudeUsage` is absent in the MSIX install.
3. Sign out and back in. Confirm only one app instance runs, it starts silently
   in the notification area without opening the flyout, and its tray/flyout/
   widget remain usable.
4. Exercise Korean and English at 100%, 125%, 150%, and 200% display scaling.
5. Exercise Codex-only use without Claude login. Then complete Claude login in
   the isolated WebView2 window. Never automate or record credentials.
6. Confirm settings/history/session files are under
   `%LOCALAPPDATA%\ClaudeUsage`, while provider auth remains provider-owned.
7. Publish the higher-version MSIX and replace the stable App Installer file.
   Launch again after the four-hour policy window (or use a controlled test
   channel with a fresh identity) and confirm the update is detected and the app
   restarts on the higher version without losing settings or history. Sign out
   and in once more and confirm the identity-based startup task still launches
   exactly one background instance after the versioned package path changes.
8. Use Windows Settings > Apps > Installed apps to uninstall. Confirm the Start
   entry, tray process, binaries, and package registration disappear.
9. Confirm `%LOCALAPPDATA%\ClaudeUsage`, `%USERPROFILE%\.claude`, and
   `%USERPROFILE%\.codex` remain. Reinstall and confirm settings/history can be
   read again.

## Failure gates

Do not release if any of these occur:

- unsigned/invalid/timestamp-less package or publisher mismatch
- update changes Name or Publisher, downgrades unexpectedly, or loses state
- uninstall removes ClaudeUsage user data or any provider-owned data
- SmartScreen or App Installer reports an unknown/untrusted publisher
- clean-machine launch needs a system-wide .NET installation
- WebView2, Codex-only, tray startup, DPI, or accessibility smoke fails
- the hosted `.appinstaller`/MSIX response lacks correct content type or length

Archive the completed checklist and exact hashes with the release approval. For
a public workflow run, download the signed artifact produced by the candidate
job and approve the waiting `windows-production-release` job only after the
record is attached. Publication reuses that exact artifact; it does not rebuild.
