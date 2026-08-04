# Windows installer (Advanced Installer)

This folder holds the Advanced Installer workflow for Hesabix Windows desktop.

## Prerequisites

1. Build Flutter release first:
   ```powershell
   .\build_windows.ps1 -Mode release
   ```
   Output folder (default):
   `hesabixUI\hesabix_ui\build\windows\x64\runner\Release`

2. Install [Advanced Installer](https://www.advancedinstaller.com/) (Professional or higher recommended for CLI packaging).

3. **Code-signing certificate (required for production)** — unsigned MSI files are blocked by Windows SmartScreen and many enterprise policies. See [Code signing](#code-signing) below.

## Build MSI

From the repo root:

```powershell
.\build_windows_installer.ps1
```

The script:

- Locates `AdvancedInstaller.com`
- Creates/refreshes a simple AIP that packages the Flutter `Release` folder
- Sets Product Version from `pubspec.yaml` (`MAJOR.MINOR.PATCH`)
- Creates Start Menu + **Desktop** shortcuts named `Hesabix` (with app icon)
- **Signs** release binaries and the MSI when a certificate is configured
- Builds `hesabix-windows.<version>.msi` under `installer\windows\dist\`

Uses an Advanced Installer **professional** project (CLI `-type professional`).

Useful flags:

```powershell
.\build_windows_installer.ps1 -DryRun
.\build_windows_installer.ps1 -SkipNewProject   # reuse existing hesabix.aip
.\build_windows_installer.ps1 -RequireSign      # fail if no certificate is configured
.\build_windows_installer.ps1 -SkipSign         # unsigned build (dev only)
.\build_windows_installer.ps1 -AdvInstPath "C:\Program Files (x86)\Caphyon\Advanced Installer 22.0\bin\x86\AdvancedInstaller.com"
```

## Code signing

### Why installation is blocked

Windows checks the **Authenticode** signature on MSI/EXE installers. The previous pipeline built MSI files **without signing** (`Status: NotSigned`), so SmartScreen shows *"Windows protected your PC"* and some systems refuse installation entirely.

### What you need

A **Code Signing** certificate from a public CA (OV or EV), exported as `.pfx`:

| Type | SmartScreen | Notes |
|------|-------------|-------|
| **EV** | Immediate reputation | Recommended for public desktop apps |
| **OV** | Reputation builds over time | Cheaper; early downloads may still warn |
| **Self-signed** | Not trusted | Dev/testing only |

Recommended CAs: DigiCert, Sectigo, GlobalSign.

Optional: install **Windows SDK → Signing Tools for Desktop Apps** so `signtool.exe` is available (Advanced Installer and CI use it).

### Configure signing for builds

Set environment variables before `build_windows_installer.ps1`:

```powershell
$env:WIN_CODESIGN_PFX = 'C:\secrets\hesabix-codesign.pfx'
$env:WIN_CODESIGN_PASSWORD = 'your-pfx-password'
.\build_windows_installer.ps1 -RequireSign
```

Alternatives:

- Place `installer\windows\codesign.pfx` locally (gitignored) + set `WIN_CODESIGN_PASSWORD`
- Certificate already in Windows store: `$env:WIN_CODESIGN_THUMBPRINT = 'ABC123...'`
- Find by subject: `$env:WIN_CODESIGN_SUBJECT = 'Hesabix'`

Manual signing of an existing MSI:

```powershell
.\scripts\sign_windows_artifact.ps1 -Path installer\windows\dist\hesabix-windows.1.2.3.msi -Verify
```

Verify signature:

```powershell
Get-AuthenticodeSignature installer\windows\dist\hesabix-windows.*.msi | Format-List Status, StatusMessage, SignerCertificate
```

`Status` must be **Valid** with a CA-issued publisher name for end users to install without warnings.

## Publish

```powershell
$env:FORGEJO_TOKEN='...'
.\release_windows_forgejo.ps1
```

Uploads `hesabix-windows.<version>.msi` to the Forgejo release with the same tag as Android. If the release already exists (Android published first), only the Windows asset is attached/replaced — the APK is left alone.

## Client expectations

The Windows app looks for release assets named preferably:

- `hesabix-windows.<version>.msi`
- otherwise any `.msi`, then setup-like `.exe`

See `docs/WINDOWS_AUTO_UPDATE.md`.
