# AutoScrcpy — automatic USB screen mirroring on Windows

Automatically launches [scrcpy](https://github.com/Genymobile/scrcpy) when a specific Android phone connects to Windows over USB. The PowerShell watcher and scrcpy's terminal run hidden; only the phone-mirroring window appears.

## Features

- Event-driven USB device detection using `Win32_DeviceChangeEvent` (no continuous ADB polling while idle).
- Starts mirroring if the phone is already connected when the watcher launches.
- Briefly retries ADB after a device-arrival event until Android is ready.
- Avoids duplicate scrcpy windows and duplicate watcher instances.
- Records diagnostics in `%LOCALAPPDATA%\AutoScrcpy\watcher.log`.
- Can start automatically when you sign in to Windows using Task Scheduler.

## Requirements

- Windows 10/11 with PowerShell 7 (`pwsh.exe`).
- A complete [scrcpy Windows release](https://github.com/Genymobile/scrcpy/releases), including `scrcpy.exe`, `adb.exe`, and `scrcpy-noconsole.vbs`.
- USB debugging enabled on the phone, with this computer authorized for ADB.
- Phone ADB serial configured in `auto-scrcpy-hidden.ps1` (currently `cd009d47`).

## Files

| File | Purpose |
| --- | --- |
| `auto-scrcpy-hidden.ps1` | Watches Windows device events, checks ADB, and launches scrcpy. |
| `launch-auto-scrcpy-hidden.vbs` | Starts the PowerShell watcher without displaying a terminal. |

## Installation

1. Extract the complete scrcpy release into `C:\Scripts\scrcpy\` (do not commit the scrcpy binaries into this repository).
2. Copy **both** scripts into `C:\Scripts\`:

   ```text
   C:\Scripts\
   ├── auto-scrcpy-hidden.ps1
   ├── launch-auto-scrcpy-hidden.vbs
   └── scrcpy\
       ├── scrcpy.exe
       ├── adb.exe
       └── scrcpy-noconsole.vbs
   ```

3. If needed, edit `$serial = 'cd009d47'` in `auto-scrcpy-hidden.ps1` to match your phone's ID. Find it with:

   ```powershell
   & 'C:\Scripts\scrcpy\adb.exe' devices
   ```

4. Test in a **visible** PowerShell 7 window:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File 'C:\Scripts\auto-scrcpy-hidden.ps1'
   ```

   Verify mirroring works. Stop the watcher using **Ctrl+C**.

5. Double-click `C:\Scripts\launch-auto-scrcpy-hidden.vbs` to start the watcher in the background.

## Start automatically when signing in

Open PowerShell **as your normal Windows user** and run:

```powershell
$action = New-ScheduledTaskAction `
    -Execute "$env:WINDIR\System32\wscript.exe" `
    -Argument '"C:\Scripts\launch-auto-scrcpy-hidden.vbs"'

$trigger = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName 'AutoScrcpy' `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description 'Start hidden scrcpy watcher at user logon' `
    -Force
```

This task starts the watcher **when you sign in**, not before login. The watcher stays running in your user session. The scheduled task itself may show `Ready` after its launcher exits.

Verify the task:

```powershell
Get-ScheduledTask -TaskName 'AutoScrcpy'
Get-ScheduledTaskInfo -TaskName 'AutoScrcpy'
```

To start it manually:

```powershell
Start-ScheduledTask -TaskName 'AutoScrcpy'
```

## Mirroring settings

The script launches scrcpy with:

```powershell
scrcpy -s cd009d47 --video-codec=h265 --video-bit-rate=20M --max-fps=60
```

Change the serial or video options in `auto-scrcpy-hidden.ps1` as needed. To override the scrcpy installation path, set the `SCRCPY_DIR` environment variable.

## Troubleshooting

**Nothing happens when starting the `.vbs` file:** run the `.ps1` directly from a visible PowerShell 7 window to see errors.

**Check ADB authorization:**

```powershell
& 'C:\Scripts\scrcpy\adb.exe' -s cd009d47 get-state
```

Expected result: `device`. If it reports `unauthorized`, unlock the phone and approve the USB debugging prompt.

**Read watcher logs:**

```powershell
Get-Content "$env:LOCALAPPDATA\AutoScrcpy\watcher.log" -Tail 30
```

**Check the startup task:**

```powershell
Get-ScheduledTask -TaskName 'AutoScrcpy' | Format-List TaskName,State,Actions,Triggers
```

**No log file at all:** the script may have failed to start or parse. Check the file path and run it visibly.

**Duplicate instances:** the script uses a named mutex to keep one watcher running per Windows session.

## Notes

- Requires the phone to be connected and authorized through ADB; ordinary USB charging alone is insufficient.
- The watcher checks ADB briefly at startup and after device-arrival events, not continuously while idle.
- Keep credentials and other private configuration out of Git. This version contains a device serial and fixed installation paths, which may need updating on another computer.
