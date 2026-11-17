Option Explicit
Dim shell, fs, folder, scriptPath, pwsh, command
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fs.BuildPath(folder, "auto-scrcpy-hidden.ps1")
If Not fs.FileExists(scriptPath) Then
    MsgBox "Missing PowerShell script:" & vbCrLf & scriptPath, vbExclamation, "AutoScrcpy"
    WScript.Quit 1
End If
' Prefer the standard PowerShell 7 installation, even if pwsh.exe isn't on PATH.
pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If Not fs.FileExists(pwsh) Then pwsh = "pwsh.exe"
command = Chr(34) & pwsh & Chr(34) & " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34)
' 0 = hidden, False = do not block the caller. The PowerShell watcher stays alive.
shell.Run command, 0, False
