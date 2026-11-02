# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment: closes a pseudoconsole (ConPTY) with a console program on it.
#   close-console.ps1 -Log LOG -Program EXE [-Argument ARG,...] [-Wait 30]
param([string] $Log, [string] $Program, [string[]] $Argument = @(), [int] $Wait = 30)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class Pty {
  [StructLayout(LayoutKind.Sequential)] public struct Coord { public short X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct StartupInfo {
    public int cb; public IntPtr lpReserved, lpDesktop, lpTitle;
    public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)] public struct StartupInfoEx { public StartupInfo StartupInfo; public IntPtr lpAttributeList; }
  [StructLayout(LayoutKind.Sequential)] public struct ProcessInfo { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out IntPtr r, out IntPtr w, IntPtr a, int size);
  [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(Coord size, IntPtr input, IntPtr output, uint flags, out IntPtr pc);
  [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr pc);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int n, int f, ref IntPtr size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr l, uint f, IntPtr a, IntPtr v, IntPtr s, IntPtr p, IntPtr r);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref StartupInfoEx si, out ProcessInfo pi);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(IntPtr h, byte[] b, int n, out int read, IntPtr o);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);

  public static IntPtr Pc, Process, OutRead;
  // Starts a program on a new pseudoconsole; returns its process id.
  public static int Start(string commandLine, string dir) {
    IntPtr inRead, inWrite, outRead, outWrite;
    CreatePipe(out inRead, out inWrite, IntPtr.Zero, 0);
    CreatePipe(out outRead, out outWrite, IntPtr.Zero, 0);
    if (CreatePseudoConsole(new Coord { X = 120, Y = 30 }, inRead, outWrite, 0, out Pc) != 0) throw new Exception("CreatePseudoConsole");
    CloseHandle(inRead); CloseHandle(outWrite);
    OutRead = outRead;
    var drain = new Thread(() => { var b = new byte[4096]; int n; while (ReadFile(outRead, b, b.Length, out n, IntPtr.Zero) && n > 0) {} });
    drain.IsBackground = true; drain.Start();
    IntPtr size = IntPtr.Zero;
    InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
    var si = new StartupInfoEx(); si.StartupInfo.cb = Marshal.SizeOf(typeof(StartupInfoEx));
    si.lpAttributeList = Marshal.AllocHGlobal(size);
    if (!InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, ref size)) throw new Exception("Initialize");
    if (!UpdateProcThreadAttribute(si.lpAttributeList, 0, (IntPtr)0x20016, Pc, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) throw new Exception("Update");
    ProcessInfo pi;
    if (!CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, false, 0x80000, IntPtr.Zero, dir, ref si, out pi))
      throw new System.ComponentModel.Win32Exception();
    Process = pi.hProcess;
    return pi.dwProcessId;
  }
  public static void Close() { ClosePseudoConsole(Pc); }
  // Waits for the program to end; returns its exit code, or -1 if it did not.
  public static long Await(int seconds) {
    if (WaitForSingleObject(Process, (uint)(seconds * 1000)) != 0) return -1;
    uint code; GetExitCodeProcess(Process, out code); return code;
  }
  public static void Kill() { TerminateProcess(Process, 99); }
}
'@

function Await([scriptblock] $Test) {
  for ($tick = 0; $tick -lt 300; $tick++) { if (& $Test) { return $true }; Start-Sleep -Milliseconds 100 }
  return $false
}

Remove-Item -LiteralPath $Log -ErrorAction SilentlyContinue
$line = (@("`"$Program`"") + ($Argument | ForEach-Object { "`"$_`"" }) + "`"$Log`"") -join ' '
Write-Host "starting: $line"
$id = [Pty]::Start($line, $env:SystemRoot)
if (-not (Await { (Test-Path -LiteralPath $Log) -and (Get-Content -LiteralPath $Log) -contains 'ready' })) {
  [Pty]::Kill(); throw "never ready"
}
Write-Host "ready; closing the pseudoconsole"
$clock = [Diagnostics.Stopwatch]::StartNew()
[Pty]::Close()
$code = [Pty]::Await($Wait)
Write-Host ("ended after {0:n1}s with exit code {1}" -f $clock.Elapsed.TotalSeconds, $code)
if ($code -eq -1) { [Pty]::Kill() }
Write-Host "log:"
Get-Content -LiteralPath $Log | ForEach-Object { Write-Host "  $_" }
