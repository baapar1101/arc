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

3. Optional but recommended: a code-signing certificate for the MSI.

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
- Builds `hesabix-windows.<version>.msi` under `installer\windows\dist\`

Uses an Advanced Installer **professional** project (CLI `-type professional`).

Useful flags:

```powershell
.\build_windows_installer.ps1 -DryRun
.\build_windows_installer.ps1 -SkipNewProject   # reuse existing hesabix.aip
.\build_windows_installer.ps1 -AdvInstPath "C:\Program Files (x86)\Caphyon\Advanced Installer 22.0\bin\x86\AdvancedInstaller.com"
```

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
