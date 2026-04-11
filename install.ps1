# ─────────────────────────────────────────────────
#  Uni Watch — Installer Script (Windows PowerShell)
#  Run with: powershell -ExecutionPolicy Bypass -File install.ps1
# ─────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ── Colours / Helpers ─────────────────────────────
function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Line    { Write-Host "──────────────────────────────────────────────" -ForegroundColor Cyan }
function Write-Ask     { param($msg) Write-Host "[INPUT] $msg" -ForegroundColor Yellow }

# Adds a folder to the current session PATH (no duplicates)
function Add-ToSessionPath {
    param([string]$folder)
    if ($folder -and (Test-Path $folder)) {
        if ($env:Path -notlike "*$folder*") {
            $env:Path = "$folder;$env:Path"
            Write-Info "Added to session PATH: $folder"
        }
    }
}

# Returns all Python Scripts directories for the current user
function Get-PythonScriptsDirs {
    $dirs = @()

    # From where python.exe actually lives
    foreach ($cmd in @("python", "python3", "py")) {
        try {
            $exe = (Get-Command $cmd -ErrorAction SilentlyContinue).Source
            if ($exe) {
                $dirs += (Join-Path (Split-Path $exe) "Scripts")
                $dirs += (Join-Path (Split-Path $exe -Parent) "Scripts")
            }
        } catch {}
    }

    # Roaming user Scripts folders (covers --user installs)
    $roaming = $env:APPDATA
    if ($roaming) {
        Get-ChildItem "$roaming\Python" -ErrorAction SilentlyContinue |
            ForEach-Object { $dirs += "$($_.FullName)\Scripts" }
    }

    # Local user Scripts folders
    $localApp = $env:LOCALAPPDATA
    if ($localApp) {
        Get-ChildItem "$localApp\Programs\Python" -ErrorAction SilentlyContinue |
            ForEach-Object { $dirs += "$($_.FullName)\Scripts" }
    }

    # pipx default bin dir
    $dirs += "$env:USERPROFILE\.local\bin"

    return $dirs | Select-Object -Unique
}

# ── Banner ────────────────────────────────────────
Clear-Host
Write-Line
Write-Host "         Uni Watch - Auto Installer" -ForegroundColor White
Write-Host "         Sets up everything and launches the app" -ForegroundColor Gray
Write-Line
Write-Host ""

# ── Step 1: Detect Windows ────────────────────────
Write-Info "Detecting operating system..."
$osInfo    = Get-CimInstance Win32_OperatingSystem
$osCaption = $osInfo.Caption
$osArch    = $osInfo.OSArchitecture
Write-Ok "System detected: $osCaption ($osArch)"
Write-Host ""

# ── Step 2: Check Python ──────────────────────────
Write-Info "Checking for Python 3.9+..."

$pythonCmd = $null
$pythonOk  = $false

foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python (\d+)\.(\d+)") {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            if ($major -ge 3 -and $minor -ge 9) {
                $pythonCmd = $cmd
                $pythonOk  = $true
                Write-Ok "Python $major.$minor found."
                break
            } else {
                Write-Warn "Python $major.$minor found but 3.9+ is required."
            }
        }
    } catch {}
}

Write-Host ""

# ── Step 3: Install Python if missing ─────────────
if (-not $pythonOk) {
    Write-Warn "Python 3.9+ was not found on your system."
    Write-Host ""
    Write-Ask "Would you like this script to install Python for you? (yes/no)"
    $userChoice = Read-Host
    Write-Host ""

    if ($userChoice -match "^[Yy](es?)?$") {
        Write-Info "Installing Python 3.11..."

        $useWinget = $false
        try { $null = & winget --version 2>&1; $useWinget = $true } catch {}

        if ($useWinget) {
            winget install --id Python.Python.3.11 `
                --silent `
                --accept-package-agreements `
                --accept-source-agreements
        } else {
            Write-Info "winget not available. Downloading Python installer..."
            $installerUrl  = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $installerPath = "$env:TEMP\python_installer.exe"
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            Write-Info "Running Python installer (this may take a moment)..."
            Start-Process -FilePath $installerPath `
                -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" `
                -Wait
            Remove-Item $installerPath -Force
        }

        # Reload system + user PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        # Inject any new Python Scripts dirs
        foreach ($d in (Get-PythonScriptsDirs)) { Add-ToSessionPath $d }

        foreach ($cmd in @("python", "py")) {
            try {
                $ver = & $cmd --version 2>&1
                if ($ver -match "Python 3") {
                    $pythonCmd = $cmd
                    $pythonOk  = $true
                    Write-Ok "Python installed successfully: $ver"
                    break
                }
            } catch {}
        }

        if (-not $pythonOk) {
            Write-Err "Python installation failed or PATH was not updated."
            Write-Err "Please restart this terminal and re-run the script."
            Write-Err "Or install Python manually: https://www.python.org/downloads/"
            exit 1
        }

    } else {
        Write-Host ""
        Write-Warn "Python installation skipped."
        Write-Info "Please install Python 3.9+ manually from:"
        Write-Info "  https://www.python.org/downloads/"
        Write-Info "Then re-run this script."
        Write-Host ""
        exit 0
    }
}

Write-Host ""

# ── Step 4: Inject all known Python Scripts dirs ──
# Do this early so pip / pipx picked up by --user installs are found
foreach ($d in (Get-PythonScriptsDirs)) { Add-ToSessionPath $d }

# ── Step 5: Ensure pip is available ───────────────
Write-Info "Checking pip..."

$pipOk = $false
try { $null = & $pythonCmd -m pip --version 2>&1; $pipOk = $true } catch {}

if (-not $pipOk) {
    Write-Warn "pip not found. Installing pip..."
    $getPipPath = "$env:TEMP\get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" `
        -OutFile $getPipPath -UseBasicParsing
    & $pythonCmd $getPipPath
    Remove-Item $getPipPath -Force

    # Re-inject Scripts dirs after pip install
    foreach ($d in (Get-PythonScriptsDirs)) { Add-ToSessionPath $d }
}

Write-Ok "pip is available."
Write-Host ""

# ── Step 6: Install pipx ──────────────────────────
Write-Info "Installing pipx..."

# Helper: find pipx.exe anywhere in known Scripts dirs
function Find-Pipx {
    foreach ($d in (Get-PythonScriptsDirs)) {
        $candidate = Join-Path $d "pipx.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    # Also try plain command
    $found = Get-Command pipx -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

$pipxExe = Find-Pipx

if ($pipxExe) {
    Write-Ok "pipx is already installed at: $pipxExe"
} else {
    # Install pipx
    & $pythonCmd -m pip install --quiet --upgrade pipx

    # Re-inject Scripts dirs so the new pipx.exe is visible
    foreach ($d in (Get-PythonScriptsDirs)) { Add-ToSessionPath $d }

    # Run ensurepath via module (avoids needing pipx on PATH yet)
    & $pythonCmd -m pipx ensurepath 2>&1 | Out-Null

    # Re-inject once more after ensurepath
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    foreach ($d in (Get-PythonScriptsDirs)) { Add-ToSessionPath $d }

    $pipxExe = Find-Pipx

    if (-not $pipxExe) {
        Write-Err "pipx was installed but could not be located."
        Write-Err "Please close this terminal, open a new one, and run:"
        Write-Err "  pipx install uni-watch"
        exit 1
    }

    Write-Ok "pipx installed at: $pipxExe"
}

Write-Host ""

# ── Step 7: Install Uni Watch ─────────────────────
Write-Info "Installing Uni Watch via pipx..."

$pipxList = & $pipxExe list 2>&1
if ($pipxList -match "uni-watch") {
    Write-Warn "Uni Watch is already installed. Upgrading to latest version..."
    try { & $pipxExe upgrade uni-watch } catch {}
} else {
    & $pipxExe install uni-watch
}

# Inject pipx bin dir so uni-watch command is found
$pipxBin = & $pythonCmd -c "import pipx.constants; print(pipx.constants.LOCAL_BIN_DIR)" 2>&1
if ($pipxBin -and (Test-Path $pipxBin)) {
    Add-ToSessionPath $pipxBin
}
# Also inject the standard fallback
Add-ToSessionPath "$env:USERPROFILE\.local\bin"

Write-Ok "Uni Watch is ready."
Write-Host ""

# ── Step 8: Launch ────────────────────────────────
Write-Line
Write-Ok "Setup complete! Launching Uni Watch..."
Write-Line
Write-Host ""

# Locate uni-watch.exe directly in case PATH still lags
$uniExe = Get-Command uni-watch -ErrorAction SilentlyContinue
if ($uniExe) {
    & $uniExe.Source
} else {
    # Fallback: search Scripts dirs
    $found = $false
    foreach ($d in (Get-PythonScriptsDirs)) {
        $candidate = Join-Path $d "uni-watch.exe"
        if (Test-Path $candidate) {
            & $candidate
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Err "Could not locate uni-watch executable."
        Write-Err "Please open a new terminal and run: uni-watch"
    }
}

Write-Host ""
Write-Line
Write-Info "Uni Watch has exited. Run it again anytime with: uni-watch"
Write-Line
