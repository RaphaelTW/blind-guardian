#requires -PSEdition Desktop
# Tenta iniciar um executável inofensivo com o token do próprio usuário.
# Não testa conta dedicada nem aplica política AppLocker.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class BrokerProcessProbe {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public uint cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public uint dwX;
        public uint dwY;
        public uint dwXSize;
        public uint dwYSize;
        public uint dwXCountChars;
        public uint dwYCountChars;
        public uint dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool DuplicateTokenEx(IntPtr existing, uint access, IntPtr attributes, int impersonationLevel, int tokenType, out IntPtr token);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateProcessAsUserW")]
    public static extern bool CreateProcessAsUser(IntPtr token, string app, StringBuilder command,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags,
        IntPtr environment, string directory, ref STARTUPINFO startup, out PROCESS_INFORMATION process);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr handle, out uint exitCode);
}
'@
Add-Type -TypeDefinition $source -ErrorAction Stop

$sourceToken = [IntPtr]::Zero
$primaryToken = [IntPtr]::Zero
$process = New-Object BrokerProcessProbe+PROCESS_INFORMATION
try {
    if (-not [BrokerProcessProbe]::OpenProcessToken([BrokerProcessProbe]::GetCurrentProcess(), 0xB, [ref]$sourceToken)) {
        throw "OpenProcessToken falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    if (-not [BrokerProcessProbe]::DuplicateTokenEx($sourceToken, 0x02000000, [IntPtr]::Zero, 2, 1, [ref]$primaryToken)) {
        throw "DuplicateTokenEx falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    $startup = New-Object BrokerProcessProbe+STARTUPINFO
    $startup.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][BrokerProcessProbe+STARTUPINFO])
    $app = Join-Path $env:WINDIR 'System32\whoami.exe'
    $command = [Text.StringBuilder]::new('whoami.exe /user')
    $ok = [BrokerProcessProbe]::CreateProcessAsUser($primaryToken, $app, $command,
        [IntPtr]::Zero, [IntPtr]::Zero, $false, 0x08000000,
        [IntPtr]::Zero, (Split-Path -Parent $app), [ref]$startup, [ref]$process)
    if (-not $ok) { throw "CreateProcessAsUserW falhou: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    [void][BrokerProcessProbe]::WaitForSingleObject($process.hProcess, 10000)
    $exitCode = [uint32]0
    [void][BrokerProcessProbe]::GetExitCodeProcess($process.hProcess, [ref]$exitCode)
    [pscustomobject]@{ProcessId=$process.dwProcessId; ExitCode=$exitCode; TokenSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
} finally {
    if ($process.hThread -ne [IntPtr]::Zero) { [void][BrokerProcessProbe]::CloseHandle($process.hThread) }
    if ($process.hProcess -ne [IntPtr]::Zero) { [void][BrokerProcessProbe]::CloseHandle($process.hProcess) }
    if ($primaryToken -ne [IntPtr]::Zero) { [void][BrokerProcessProbe]::CloseHandle($primaryToken) }
    if ($sourceToken -ne [IntPtr]::Zero) { [void][BrokerProcessProbe]::CloseHandle($sourceToken) }
}
