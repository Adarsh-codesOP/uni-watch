# ─────────────────────────────────────────────────
#  Uni Watch — Installer Script (Windows PowerShell)
#  Run with: powershell -ExecutionPolicy Bypass -File install.ps1
# ─────────────────────────────────────────────────

$ErrorActionPreference = "SilentlyContinue"

# ── Helpers ───────────────────────────────────────
function Write-Info { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Line { Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan }
function Write-Ask  { param($msg) Write-Host "[INPUT] $msg" -ForegroundColor Yellow }

# Silently add a path to the current session (no duplicates)
function Add-ToSessionPath([string]$folder) {
    if ($folder -and (Test-Path $folder) -and ($env:Path -notlike "*$folder*")) {
        $env:Path = "$folder;$env:Path"
    }
}

# Permanently add a path to the user PATH in registry + session
function Add-ToUserPath([string]$folder) {
    if (-not $folder -or -not (Test-Path $folder)) { return }
    $current = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$folder*") {
        [System.Environment]::SetEnvironmentVariable(
            "Path", "$current;$folder", "User")
        Write-Ok "Permanently added to user PATH: $folder"
    }
    Add-ToSessionPath $folder
}

# ── Fix pipx paths — avoids the "space in path" warning ──
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
$os = Get-CimInstance Win32_OperatingSystem
Write-Ok "System detected: $($os.Caption) ($($os.OSArchitecture))"
Write-Host ""

# ── Step 2: Find Python ───────────────────────────
Write-Info "Checking for Python 3.9+..."

# Reload PATH from registry first so anything already installed is visible
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

$pythonCmd = $null
$pythonOk  = $false

foreach ($cmd in @("python", "python3", "py")) {
    $exe = (Get-Command $cmd -ErrorAction SilentlyContinue)?.Source
    if (-not $exe) { continue }
    $ver = & $exe --version 2>&1
    if ($ver -match "Python (\d+)\.(\d+)") {
        if ([int]$Matches[1] -ge 3 -and [int]$Matches[2] -ge 9) {
            $pythonCmd = $exe          # store the full path, not just cmd name
            $pythonOk  = $true
            Write-Ok "Python $($Matches[1]).$($Matches[2]) found at: $exe"
            break
        } else {
            Write-Warn "Python $($Matches[1]).$($Matches[2]) is below 3.9 — skipping."
        }
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
            winget install --id Python.Python.3.11 --silent `
                --accept-package-agreements --accept-source-agreements
        } else {
            $url  = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $dest = "$env:TEMP\python_installer.exe"
            Write-Info "Downloading Python installer..."
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            Start-Process -FilePath $dest `
                -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" `
                -Wait
            Remove-Item $dest -Force
        }

        # Reload PATH after install
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        foreach ($cmd in @("python", "py")) {
            $exe = (Get-Command $cmd -ErrorAction SilentlyContinue)?.Source
            if (-not $exe) { continue }
            $ver = & $exe --version 2>&1
            if ($ver -match "Python 3") {
                $pythonCmd = $exe
                $pythonOk  = $true
                Write-Ok "Python installed: $ver"
                break
            }
        }

        if (-not $pythonOk) {
            Write-Err "Python install failed. Please install manually:"
            Write-Err "  https://www.python.org/downloads/"
            Write-Err "Then re-run this script."
            exit 1
        }
    } else {
        Write-Warn "Skipped. Install Python 3.9+ from https://www.python.org/downloads/ then re-run."
        exit 0
    }
}

Write-Host ""

# ── Step 4: Ensure pip works ──────────────────────
Write-Info "Checking pip..."

# Collect all Python Scripts dirs for this user and inject them
$scriptsDirs = @()

# From the python exe location itself
$pyDir = Split-Path $pythonCmd
$scriptsDirs += $pyDir
$scriptsDirs += (Join-Path $pyDir "Scripts")

# Roaming user installs (e.g. Python314\Scripts)
Get-ChildItem "$env:APPDATA\Python" -ErrorAction SilentlyContinue |
    ForEach-Object { $scriptsDirs += "$($_.FullName)\Scripts" }

# Local user installs
Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -ErrorAction SilentlyContinue |
    ForEach-Object { $scriptsDirs += "$($_.FullName)\Scripts" }

# pipx bin dirs
$scriptsDirs += "$env:USERPROFILE\.local\bin"
$scriptsDirs += "$env:PIPX_BIN_DIR"

foreach ($d in ($scriptsDirs | Select-Object -Unique)) {
    Add-ToSessionPath $d
}

# Try pip in several ways
$pipOk = $false
foreach ($pipCmd in @("pip", "pip3", "pip.exe")) {
    if (Get-Command $pipCmd -ErrorAction SilentlyContinue) {
        $pipOk = $true
        Write-Ok "pip found: $pipCmd"
        break
    }
}

# Also try via python -m pip
if (-not $pipOk) {
    $check = & $pythonCmd -m pip --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pipOk = $true
        Write-Ok "pip available via python -m pip"
    }
}

if (-not $pipOk) {
    Write-Warn "pip not found. Bootstrapping pip..."
    $getPip = "$env:TEMP\get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip -UseBasicParsing
    & $pythonCmd $getPip
    Remove-Item $getPip -Force
    foreach ($d in ($scriptsDirs | Select-Object -Unique)) { Add-ToSessionPath $d }
    Write-Ok "pip installed."
}

Write-Host ""

# ── Step 5: Install pipx ──────────────────────────
Write-Info "Installing pipx..."

# Check if pipx is already usable
$pipxExe = (Get-Command pipx -ErrorAction SilentlyContinue)?.Source

if (-not $pipxExe) {
    # Install via python -m pip (most reliable)
    & $pythonCmd -m pip install --quiet --upgrade pipx

    # Re-inject all Scripts dirs
    foreach ($d in ($scriptsDirs | Select-Object -Unique)) { Add-ToSessionPath $d }

    # Run ensurepath via module (works even if pipx.exe not on PATH yet)
    & $pythonCmd -m pipx ensurepath --force 2>&1 | Out-Null

    # Reload registry PATH + re-inject
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    foreach ($d in ($scriptsDirs | Select-Object -Unique)) { Add-ToSessionPath $d }

    # Find pipx.exe by scanning all Scripts dirs
    foreach ($d in ($scriptsDirs | Select-Object -Unique)) {
        $candidate = Join-Path $d "pipx.exe"
        if (Test-Path $candidate) { $pipxExe = $candidate; break }
    }

    # Last resort: python -m pipx works even without pipx.exe on PATH
    if (-not $pipxExe) {
        Write-Warn "pipx.exe not found on PATH — will use 'python -m pipx' instead."
        $pipxExe = $null   # handled below via $pipxCall
    } else {
        Write-Ok "pipx found at: $pipxExe"
    }
} else {
    Write-Ok "pipx already installed at: $pipxExe"
}

# Build a callable for pipx that works regardless
$pipxCall = if ($pipxExe) { { & $pipxExe @args } } `
            else           { { & $pythonCmd -m pipx @args } }

Write-Host ""

# ── Step 6: Install Uni Watch ─────────────────────
Write-Info "Installing Uni Watch via pipx..."

$listOut = & $pipxCall list 2>&1
if ($listOut -match "uni-watch") {
    Write-Warn "Already installed — upgrading..."
    & $pipxCall upgrade uni-watch 2>&1 | Out-Null
} else {
    & $pipxCall install uni-watch
}

# ── Step 7: Add uni-watch to PATH permanently ─────
Write-Info "Adding uni-watch to user PATH..."

# pipx puts binaries in PIPX_BIN_DIR
$binDirs = @(
    $env:PIPX_BIN_DIR,
    "$env:USERPROFILE\.local\bin"
)

foreach ($d in $binDirs) {
    if ($d -and (Test-Path $d)) {
        $uniCandidate = Join-Path $d "uni-watch.exe"
        if (Test-Path $uniCandidate) {
            Add-ToUserPath $d
            $uniExePath = $uniCandidate
            break
        }
    }
}

# Also scan all Scripts dirs as fallback
if (-not $uniExePath) {
    foreach ($d in ($scriptsDirs | Select-Object -Unique)) {
        $candidate = Join-Path $d "uni-watch.exe"
        if (Test-Path $candidate) {
            Add-ToUserPath $d
            $uniExePath = $candidate
            break
        }
    }
}

if ($uniExePath) {
    Write-Ok "uni-watch located at: $uniExePath"
} else {
    Write-Warn "uni-watch.exe not found yet — it may need a fresh terminal to appear on PATH."
}

Write-Ok "Uni Watch is ready."
Write-Host ""

# ── Step 8: Launch ────────────────────────────────
Write-Line
Write-Ok "Setup complete! Launching Uni Watch..."
Write-Line
Write-Host ""

if ($uniExePath -and (Test-Path $uniExePath)) {
    & $uniExePath
} elseif (Get-Command uni-watch -ErrorAction SilentlyContinue) {
    uni-watch
} else {
    Write-Err "Could not launch uni-watch automatically."
    Write-Err "Please open a new terminal and run: uni-watch"
    exit 1
}

Write-Host ""
Write-Line
Write-Info "Uni Watch has exited. Run it again anytime with: uni-watch"
Write-Line
