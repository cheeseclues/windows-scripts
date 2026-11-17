# AutoScrcpy - event-driven, console-free auto launch for Windows / PowerShell 7.
# Run visibly once for diagnostics. Run via launch-auto-scrcpy-hidden.vbs to hide watcher.
# Phone serial: cd009d47
# scrcpy installation: C:\Scripts\scrcpy (or set SCRCPY_DIR environment variable)

$ErrorActionPreference = 'Stop'
$serial = 'cd009d47'
$sourceId = 'AutoScrcpy.DeviceChange'
$logDir = Join-Path $env:LOCALAPPDATA 'AutoScrcpy'
$logFile = Join-Path $logDir 'watcher.log'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding utf8
    Write-Host $line
}

function Resolve-ScrcpyDir {
    if ($env:SCRCPY_DIR) {
        if (Test-Path -LiteralPath (Join-Path $env:SCRCPY_DIR 'scrcpy.exe') -PathType Leaf) {
            return $env:SCRCPY_DIR
        }
        throw "SCRCPY_DIR points to an invalid scrcpy folder: $env:SCRCPY_DIR"
    }

    # The repo may be cloned elsewhere; keep installed scrcpy under C:\Scripts\scrcpy.
    $candidates = @(
        (Join-Path $PSScriptRoot 'scrcpy'),
        'C:\Scripts\scrcpy',
        'C:\Scripts'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'scrcpy.exe') -PathType Leaf) {
            return $candidate
        }
    }

    $cmd = Get-Command scrcpy.exe -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path -Parent $cmd.Source) }
    throw 'scrcpy.exe not found. Install at C:\Scripts\scrcpy or set SCRCPY_DIR.'
}

function Test-PhoneReady {
    try {
        $state = & $script:adbPath -s $serial get-state 2>$null
        return ($LASTEXITCODE -eq 0 -and (($state -join '').Trim() -eq 'device'))
    } catch {
        return $false
    }
}

function Test-ScrcpyRunning {
    # The command line includes '-s cd009d47' when this watcher launches scrcpy.
    # This prevents duplicate windows on repeated Windows device-arrival events.
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'scrcpy.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($serial) })
    return ($processes.Count -gt 0)
}

function Start-PhoneScrcpy {
    if (Test-ScrcpyRunning) {
        Write-Log 'scrcpy is already running for this phone; ignoring duplicate event.'
        return
    }

    # scrcpy-noconsole.vbs ships with official Windows releases of scrcpy.
    # wscript.exe executes it without a console; the mirrored phone window remains visible.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Join-Path $env:WINDIR 'System32\wscript.exe'
    $psi.WorkingDirectory = $script:scrcpyDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($arg in @(
        '//B', $script:noConsoleScript,
        '-s', $serial,
        '--video-codec=h265',
        '--video-bit-rate=20M',
        '--max-fps=60'
    )) {
        [void] $psi.ArgumentList.Add($arg)
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) { throw 'Could not start wscript.exe.' }
    $process.Dispose()
    Write-Log "Launched scrcpy-noconsole.vbs for $serial."
}

# Named mutex keeps one watcher per signed-in Windows session.
$mutex = [System.Threading.Mutex]::new($false, 'Local\AutoScrcpyWatcher-cd009d47')
$ownsMutex = $false
$subscribed = $false

try {
    $ownsMutex = $mutex.WaitOne(0)
    if (-not $ownsMutex) {
        Write-Log 'Another AutoScrcpy watcher is already running; exiting.'
        return
    }

    $scrcpyDir = Resolve-ScrcpyDir
    $noConsoleScript = Join-Path $scrcpyDir 'scrcpy-noconsole.vbs'
    if (-not (Test-Path -LiteralPath $noConsoleScript -PathType Leaf)) {
        throw "Missing official scrcpy-noconsole.vbs in $scrcpyDir"
    }

    $adbPath = Join-Path $scrcpyDir 'adb.exe'
    if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
        $adbCmd = Get-Command adb.exe -ErrorAction SilentlyContinue
        if (-not $adbCmd) { throw 'adb.exe not found in scrcpy directory or PATH.' }
        $adbPath = $adbCmd.Source
    }

    Write-Log "Watcher started. scrcpyDir=$scrcpyDir; adb=$adbPath; serial=$serial"

    # Subscribe to Windows device arrival/removal; no repeated checks while idle.
    Register-CimIndicationEvent -Namespace 'root/cimv2' `
        -Query 'SELECT * FROM Win32_DeviceChangeEvent WHERE EventType = 2 OR EventType = 3' `
        -SourceIdentifier $sourceId | Out-Null
    $subscribed = $true
    Write-Log 'Windows USB device-change subscription active.'

    # Also handles the phone being connected before the watcher starts.
    $initialReady = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        if (Test-PhoneReady) {
            $initialReady = $true
            Write-Log 'Phone is already connected and ADB-ready.'
            Start-PhoneScrcpy
            break
        }
        if ($attempt -lt 12) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $initialReady) { Write-Log 'Waiting for Windows device-arrival event.' }

    while ($true) {
        $evt = Wait-Event -SourceIdentifier $sourceId
        if ($null -eq $evt) { continue }
        Remove-Event -EventIdentifier $evt.EventIdentifier

        $eventType = [int]$evt.SourceEventArgs.NewEvent.EventType
        if ($eventType -ne 2) { continue }  # 3 = device removal

        # Short temporary retries only after an arrival (Android ADB may take a moment).
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            if (Test-PhoneReady) {
                Write-Log 'ADB device ready after Windows device-arrival event.'
                Start-PhoneScrcpy
                break
            }
            if ($attempt -lt 20) { Start-Sleep -Milliseconds 750 }
        }
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    throw
} finally {
    if ($subscribed) {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue |
            Remove-Event -ErrorAction SilentlyContinue
    }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
