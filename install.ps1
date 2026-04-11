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

# ── Banner ────────────────────────────────────────
Clear-Host
Write-Line
Write-Host "         Uni Watch - Auto Installer" -ForegroundColor White
Write-Host "         Sets up everything and launches the app" -ForegroundColor Gray
Write-Line
Write-Host ""

# ── Step 1: Detect Windows ────────────────────────
Write-Info "Detecting operating system..."

$osInfo = Get-CimInstance Win32_OperatingSystem
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
    } catch {
        # Command not found — try next
    }
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

        Write-Info "Checking for winget (Windows Package Manager)..."

        $useWinget = $false
        try {
            $null = & winget --version 2>&1
            $useWinget = $true
        } catch {}

        if ($useWinget) {
            Write-Info "Installing Python 3.11 via winget..."
            winget install --id Python.Python.3.11 `
                --silent `
                --accept-package-agreements `
                --accept-source-agreements

        } else {
            Write-Info "winget not available. Downloading Python installer..."

            $installerUrl  = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $installerPath = "$env:TEMP\python_installer.exe"

            Write-Info "Downloading from: $installerUrl"
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

            Write-Info "Running Python installer (this may take a moment)..."
            Start-Process -FilePath $installerPath `
                -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" `
                -Wait

            Remove-Item $installerPath -Force
        }

        # Refresh PATH so python is found in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        # Verify
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
            Write-Err "Or install Python manually from: https://www.python.org/downloads/"
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

# ── Step 4: Ensure pip is available ───────────────
Write-Info "Checking pip..."

try {
    $null = & $pythonCmd -m pip --version 2>&1
    Write-Ok "pip is available."
} catch {
    Write-Warn "pip not found. Installing pip..."
    $getPipPath = "$env:TEMP\get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" `
        -OutFile $getPipPath -UseBasicParsing
    & $pythonCmd $getPipPath
    Remove-Item $getPipPath -Force
    Write-Ok "pip installed."
}

Write-Host ""

# ── Step 5: Install pipx ──────────────────────────
Write-Info "Installing pipx..."

$pipxInstalled = $false
try {
    $null = & pipx --version 2>&1
    $pipxInstalled = $true
    Write-Ok "pipx is already installed."
} catch {}

if (-not $pipxInstalled) {
    & $pythonCmd -m pip install --quiet --upgrade pipx
    & $pythonCmd -m pipx ensurepath

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path += ";$env:USERPROFILE\.local\bin"

    try {
        $null = & pipx --version 2>&1
        Write-Ok "pipx installed successfully."
    } catch {
        Write-Err "pipx installation failed."
        Write-Err "Try restarting your terminal and running: pipx install uni-watch"
        exit 1
    }
}

Write-Host ""

# ── Step 6: Install Uni Watch ─────────────────────
Write-Info "Installing Uni Watch via pipx..."

$pipxList = & pipx list 2>&1
if ($pipxList -match "uni-watch") {
    Write-Warn "Uni Watch is already installed. Upgrading to latest version..."
    try { pipx upgrade uni-watch } catch {}
} else {
    pipx install uni-watch
}

Write-Ok "Uni Watch is ready."
Write-Host ""

# ── Step 7: Launch ────────────────────────────────
Write-Line
Write-Ok "Setup complete! Launching Uni Watch..."
Write-Line
Write-Host ""

uni-watch

Write-Host ""
Write-Line
Write-Info "Uni Watch has exited. Run it again anytime with: uni-watch"
Write-Line
