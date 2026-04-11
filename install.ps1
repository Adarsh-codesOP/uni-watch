# ─────────────────────────────────────────────────
#  Uni Watch — Installer Script (Windows PowerShell)
#  Compatible with PowerShell 5.1 and above
#  Run with: powershell -ExecutionPolicy Bypass -File install.ps1
#         or: iex (irm https://raw.githubusercontent.com/.../install.ps1)
# ─────────────────────────────────────────────────

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

# ── Helpers ───────────────────────────────────────
function Write-Info { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Line { Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan }
function Write-Ask  { param($msg) Write-Host "[INPUT] $msg" -ForegroundColor Yellow }

# PS 5.1-safe: get command source without ?. operator
function Get-CommandSource([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Add to current session PATH (no duplicates)
function Add-ToSessionPath([string]$folder) {
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    if (-not (Test-Path $folder))              { return }
    if ($env:Path -like "*$folder*")           { return }
    $env:Path = "$folder;$env:Path"
}

# Add permanently to user PATH in registry and current session
function Add-ToUserPath([string]$folder) {
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    if (-not (Test-Path $folder))              { return }
    $current = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$folder*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$current;$folder", "User")
        Write-Ok "Permanently added to user PATH: $folder"
    }
    Add-ToSessionPath $folder
}

# Reload PATH from registry into session
function Reload-EnvPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

# Collect every directory where pip/pipx/scripts might land
function Get-AllScriptsDirs {
    $dirs = @()

    # Next to python.exe and its Scripts sibling
    foreach ($cmd in @("python", "python3", "py")) {
        $src = Get-CommandSource $cmd
        if ($src) {
            $dirs += Split-Path $src
            $dirs += (Join-Path (Split-Path $src) "Scripts")
        }
    }

    # Roaming user installs — e.g. AppData\Roaming\Python\Python314\Scripts
    if ($env:APPDATA) {
        $roaming = Get-ChildItem "$env:APPDATA\Python" -ErrorAction SilentlyContinue
        foreach ($d in $roaming) { $dirs += "$($d.FullName)\Scripts" }
    }

    # Local programs — e.g. AppData\Local\Programs\Python\Python311\Scripts
    if ($env:LOCALAPPDATA) {
        $local = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -ErrorAction SilentlyContinue
        foreach ($d in $local) { $dirs += "$($d.FullName)\Scripts" }
    }

    # pipx bin dirs (with and without space-safe override)
    $dirs += "$env:USERPROFILE\.local\bin"
    $dirs += "$env:USERPROFILE\.pipx\bin"
    $dirs += $env:PIPX_BIN_DIR

    return ($dirs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

# ── Fix pipx home — prevents "space in path" warning ──────
$env:PIPX_HOME    = "$env:USERPROFILE\.pipx"
$env:PIPX_BIN_DIR = "$env:USERPROFILE\.local\bin"

# ── Banner ────────────────────────────────────────
Clear-Host
Write-Line
Write-Host "         Uni Watch - Auto Installer" -ForegroundColor White
Write-Host "         Sets up everything and launches the app" -ForegroundColor Gray
Write-Line
Write-Host ""

# ── Step 1: Detect OS ─────────────────────────────
Write-Info "Detecting operating system..."
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Write-Ok "System detected: $($os.Caption) ($($os.OSArchitecture))"
} catch {
    Write-Ok "System detected: Windows (could not read full version)"
}
Write-Host ""

# ── Step 2: Find Python ───────────────────────────
Write-Info "Checking for Python 3.9+..."

Reload-EnvPath
foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

$pythonExe = $null
$pythonOk  = $false

foreach ($cmd in @("python", "python3", "py")) {
    $src = Get-CommandSource $cmd
    if (-not $src) { continue }

    try {
        $verOut = & $src --version 2>&1
        if ($verOut -match "Python (\d+)\.(\d+)") {
            $maj = [int]$Matches[1]
            $min = [int]$Matches[2]
            if ($maj -ge 3 -and $min -ge 9) {
                $pythonExe = $src
                $pythonOk  = $true
                Write-Ok "Python $maj.$min found at: $src"
                break
            } else {
                Write-Warn "Python $maj.$min is below 3.9 — skipping."
            }
        }
    } catch {
        Write-Warn "Could not query version from: $src"
    }
}

# Extra fallback: search common install paths directly
if (-not $pythonOk) {
    $searchRoots = @(
        "$env:LOCALAPPDATA\Programs\Python",
        "$env:APPDATA\Python",
        "C:\Python3*",
        "C:\Program Files\Python3*",
        "C:\Program Files (x86)\Python3*"
    )
    foreach ($root in $searchRoots) {
        $exes = Get-ChildItem $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
                Sort-Object -Descending
        foreach ($exe in $exes) {
            try {
                $verOut = & $exe.FullName --version 2>&1
                if ($verOut -match "Python (\d+)\.(\d+)") {
                    $maj = [int]$Matches[1]
                    $min = [int]$Matches[2]
                    if ($maj -ge 3 -and $min -ge 9) {
                        $pythonExe = $exe.FullName
                        $pythonOk  = $true
                        Write-Ok "Python $maj.$min found at: $($exe.FullName) (fallback search)"
                        Add-ToSessionPath (Split-Path $exe.FullName)
                        Add-ToSessionPath (Join-Path (Split-Path $exe.FullName) "Scripts")
                        break
                    }
                }
            } catch {}
        }
        if ($pythonOk) { break }
    }
}

Write-Host ""

# ── Step 3: Install Python if missing ─────────────
if (-not $pythonOk) {
    Write-Warn "Python 3.9+ was not found on your system."
    Write-Host ""
    Write-Ask "Would you like this script to install Python for you? (yes/no)"
    $choice = Read-Host
    Write-Host ""

    if ($choice -match "^[Yy](es?)?$") {
        Write-Info "Installing Python 3.11..."

        $hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        if ($hasWinget) {
            Write-Info "Using winget..."
            winget install --id Python.Python.3.11 --silent `
                --accept-package-agreements --accept-source-agreements
        } else {
            Write-Info "Downloading Python 3.11 installer..."
            $url  = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $dest = "$env:TEMP\python_installer.exe"
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            } catch {
                Write-Err "Download failed: $_"
                Write-Err "Please install Python manually: https://www.python.org/downloads/"
                exit 1
            }
            Write-Info "Running installer silently..."
            Start-Process -FilePath $dest `
                -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" `
                -Wait -ErrorAction Stop
            Remove-Item $dest -Force -ErrorAction SilentlyContinue
        }

        Reload-EnvPath
        foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

        foreach ($cmd in @("python", "py")) {
            $src = Get-CommandSource $cmd
            if (-not $src) { continue }
            $verOut = & $src --version 2>&1
            if ($verOut -match "Python 3") {
                $pythonExe = $src
                $pythonOk  = $true
                Write-Ok "Python installed: $verOut at $src"
                break
            }
        }

        if (-not $pythonOk) {
            Write-Err "Python install completed but still not detected."
            Write-Err "Please close this window, open a new terminal, and re-run the script."
            exit 1
        }
    } else {
        Write-Warn "Skipped. Install Python 3.9+ from https://www.python.org/downloads/ then re-run."
        exit 0
    }
}

Write-Host ""

# Refresh all scripts dirs now that we know where python lives
foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

# ── Step 4: Ensure pip ────────────────────────────
Write-Info "Checking pip..."

$pipOk = $false

# Try pip / pip3 as direct commands first
foreach ($cmd in @("pip", "pip3")) {
    $src = Get-CommandSource $cmd
    if ($src) {
        try {
            $out = & $src --version 2>&1
            if ($out -match "pip") { $pipOk = $true; Write-Ok "pip found: $src"; break }
        } catch {}
    }
}

# Try python -m pip
if (-not $pipOk) {
    try {
        $out = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -eq 0 -or $out -match "pip") {
            $pipOk = $true
            Write-Ok "pip available via: $pythonExe -m pip"
        }
    } catch {}
}

# Bootstrap pip if still missing
if (-not $pipOk) {
    Write-Warn "pip not detected — bootstrapping..."
    $getPip = "$env:TEMP\get-pip.py"
    try {
        Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" `
            -OutFile $getPip -UseBasicParsing -ErrorAction Stop
        & $pythonExe $getPip --quiet
        Remove-Item $getPip -Force -ErrorAction SilentlyContinue
        foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }
        Write-Ok "pip bootstrapped."
        $pipOk = $true
    } catch {
        Write-Err "Could not bootstrap pip: $_"
        Write-Err "Please run: $pythonExe -m ensurepip --upgrade"
        exit 1
    }
}

Write-Host ""

# ── Step 5: Install pipx ──────────────────────────
Write-Info "Installing pipx..."

# Helper: find pipx.exe by scanning all known dirs
function Find-PipxExe {
    # Try PATH first
    $src = Get-CommandSource "pipx"
    if ($src) { return $src }

    # Scan all Scripts dirs
    foreach ($d in (Get-AllScriptsDirs)) {
        $candidate = Join-Path $d "pipx.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

$pipxExe = Find-PipxExe

if ($pipxExe) {
    Write-Ok "pipx already installed at: $pipxExe"
} else {
    # Install pipx — try pip command, fall back to python -m pip
    try {
        $pipCmd = Get-CommandSource "pip"
        if ($pipCmd) {
            & $pipCmd install --quiet --upgrade pipx
        } else {
            & $pythonExe -m pip install --quiet --upgrade pipx
        }
    } catch {
        Write-Warn "pip install failed, retrying via python -m pip..."
        & $pythonExe -m pip install --quiet --upgrade pipx
    }

    # Reload PATH and rescan
    Reload-EnvPath
    foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

    # Run ensurepath via module (reliable even without pipx on PATH)
    try { & $pythonExe -m pipx ensurepath --force 2>&1 | Out-Null } catch {}

    Reload-EnvPath
    foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

    $pipxExe = Find-PipxExe

    if (-not $pipxExe) {
        Write-Warn "pipx.exe not on PATH — will invoke via: $pythonExe -m pipx"
    } else {
        Write-Ok "pipx found at: $pipxExe"
    }
}

# Unified pipx invoker — works with or without pipx.exe on PATH
function Invoke-Pipx {
    if ($pipxExe -and (Test-Path $pipxExe)) {
        & $pipxExe @args
    } else {
        & $pythonExe -m pipx @args
    }
}

Write-Host ""

# ── Step 6: Install Uni Watch ─────────────────────
Write-Info "Installing Uni Watch via pipx..."

try {
    $listOut = Invoke-Pipx list 2>&1
    if ($listOut -match "uni-watch") {
        Write-Warn "Already installed — upgrading to latest..."
        Invoke-Pipx upgrade uni-watch 2>&1 | Out-Null
        Write-Ok "Uni Watch upgraded."
    } else {
        Invoke-Pipx install uni-watch
        Write-Ok "Uni Watch installed."
    }
} catch {
    Write-Err "Failed to install Uni Watch: $_"
    Write-Err "Try manually: pipx install uni-watch"
    exit 1
}

Write-Host ""

# ── Step 7: Add uni-watch to PATH permanently ─────
Write-Info "Locating uni-watch and adding to PATH..."

Reload-EnvPath
foreach ($d in (Get-AllScriptsDirs)) { Add-ToSessionPath $d }

$uniExe = $null

# Check pipx bin dirs first
foreach ($binDir in @($env:PIPX_BIN_DIR, "$env:USERPROFILE\.local\bin", "$env:USERPROFILE\.pipx\bin")) {
    if ([string]::IsNullOrWhiteSpace($binDir)) { continue }
    $candidate = Join-Path $binDir "uni-watch.exe"
    if (Test-Path $candidate) {
        $uniExe = $candidate
        Add-ToUserPath $binDir
        break
    }
}

# Scan all Scripts dirs as fallback
if (-not $uniExe) {
    foreach ($d in (Get-AllScriptsDirs)) {
        $candidate = Join-Path $d "uni-watch.exe"
        if (Test-Path $candidate) {
            $uniExe = $candidate
            Add-ToUserPath $d
            break
        }
    }
}

# Ask pipx where it put it
if (-not $uniExe) {
    try {
        $pipxEnv = Invoke-Pipx environment 2>&1
        if ($pipxEnv -match "PIPX_BIN_DIR\s*=\s*(.+)") {
            $detectedBin = $Matches[1].Trim()
            Add-ToSessionPath $detectedBin
            Add-ToUserPath $detectedBin
            $candidate = Join-Path $detectedBin "uni-watch.exe"
            if (Test-Path $candidate) { $uniExe = $candidate }
        }
    } catch {}
}

if ($uniExe) {
    Write-Ok "uni-watch located: $uniExe"
    Write-Ok "uni-watch added to user PATH permanently."
} else {
    Write-Warn "uni-watch.exe not found yet — it may appear after opening a new terminal."
}

Write-Host ""

# ── Step 8: Launch ────────────────────────────────
Write-Line
Write-Ok "Setup complete! Launching Uni Watch..."
Write-Line
Write-Host ""

$launched = $false

if ($uniExe -and (Test-Path $uniExe)) {
    try { & $uniExe; $launched = $true } catch { Write-Warn "Direct launch failed: $_" }
}

if (-not $launched) {
    $src = Get-CommandSource "uni-watch"
    if ($src) {
        try { & $src; $launched = $true } catch { Write-Warn "PATH launch failed: $_" }
    }
}

if (-not $launched) {
    # Final fallback: python -m uni_watch
    try { & $pythonExe -m uni_watch; $launched = $true } catch {}
}

if (-not $launched) {
    Write-Err "Could not launch uni-watch automatically."
    Write-Err "Please open a NEW terminal and run: uni-watch"
    Write-Err "(PATH changes take effect in new terminals)"
}

Write-Host ""
Write-Line
Write-Info "Done. Run uni-watch anytime in a new terminal."
Write-Line
