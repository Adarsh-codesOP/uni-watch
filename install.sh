#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  Uni Watch — Installer Script (Linux / macOS)
# ─────────────────────────────────────────────

set -e

# ── Colours ──────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

line() { echo -e "${CYAN}──────────────────────────────────────────────${RESET}"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $1"; }
success() { echo -e "${GREEN}[OK]${RESET}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; }
ask()     { echo -e "${YELLOW}[INPUT]${RESET} $1"; }

# ── Banner ────────────────────────────────────
clear
line
echo -e "${BOLD}         Uni Watch — Auto Installer${RESET}"
echo -e "         Sets up everything and launches the app"
line
echo ""

# ── Step 1: Detect OS ─────────────────────────
info "Detecting operating system..."

OS=""
DISTRO=""

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    info "System detected: macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DISTRO="${ID}"
        info "System detected: Linux ($DISTRO)"
    else
        info "System detected: Linux (unknown distro)"
    fi
else
    error "Unsupported operating system: $OSTYPE"
    error "This script supports Linux and macOS only."
    exit 1
fi

echo ""

# ── Step 2: Check Python ──────────────────────
info "Checking for Python 3.9+..."

PYTHON_CMD=""
PYTHON_OK=false

for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        version=$("$cmd" --version 2>&1 | awk '{print $2}')
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        if [[ "$major" -ge 3 && "$minor" -ge 9 ]]; then
            PYTHON_CMD="$cmd"
            PYTHON_OK=true
            success "Python $version found at: $(command -v $cmd)"
            break
        else
            warn "Python $version found but version 3.9+ is required."
        fi
    fi
done

echo ""

# ── Step 3: Install Python if missing ─────────
if [ "$PYTHON_OK" = false ]; then
    warn "Python 3.9+ was not found on your system."
    echo ""
    ask "Would you like this script to install Python for you? (yes/no)"
    read -r user_choice

    echo ""

    if [[ "$user_choice" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        info "Installing Python 3..."

        if [[ "$OS" == "macos" ]]; then
            if ! command -v brew &>/dev/null; then
                info "Homebrew not found. Installing Homebrew first..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                # Add brew to PATH for Apple Silicon
                if [[ -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                fi
                success "Homebrew installed."
            fi
            brew install python@3.11
            PYTHON_CMD="python3"

        elif [[ "$OS" == "linux" ]]; then
            case "$DISTRO" in
                ubuntu|debian|linuxmint|pop)
                    sudo apt-get update -qq
                    sudo apt-get install -y python3 python3-pip python3-venv
                    ;;
                fedora)
                    sudo dnf install -y python3 python3-pip
                    ;;
                centos|rhel|almalinux|rocky)
                    sudo dnf install -y python3 python3-pip || sudo yum install -y python3 python3-pip
                    ;;
                arch|manjaro|endeavouros)
                    sudo pacman -Sy --noconfirm python python-pip
                    ;;
                opensuse*|suse*)
                    sudo zypper install -y python3 python3-pip
                    ;;
                *)
                    error "Unrecognised distro: '$DISTRO'."
                    error "Please install Python 3.9+ manually from https://www.python.org/downloads/"
                    error "Then re-run this script."
                    exit 1
                    ;;
            esac
            PYTHON_CMD="python3"
        fi

        # Verify installation
        if command -v "$PYTHON_CMD" &>/dev/null; then
            version=$("$PYTHON_CMD" --version 2>&1)
            success "Python installed successfully: $version"
        else
            error "Python installation failed. Please install it manually."
            error "Visit: https://www.python.org/downloads/"
            exit 1
        fi

    else
        echo ""
        warn "Python installation skipped."
        info  "Please install Python 3.9+ manually from:"
        info  "  https://www.python.org/downloads/"
        info  "Then re-run this script."
        echo ""
        exit 0
    fi
fi

echo ""

# ── Step 4: Ensure pip is available ───────────
info "Checking pip..."

if ! "$PYTHON_CMD" -m pip --version &>/dev/null; then
    warn "pip not found. Attempting to install pip..."
    curl -fsSL https://bootstrap.pypa.io/get-pip.py | "$PYTHON_CMD"
fi

success "pip is available."
echo ""

# ── Step 5: Install pipx ──────────────────────
info "Installing pipx..."

if command -v pipx &>/dev/null; then
    success "pipx is already installed: $(pipx --version)"
else
    "$PYTHON_CMD" -m pip install --quiet --upgrade pipx
    "$PYTHON_CMD" -m pipx ensurepath

    # Reload PATH so pipx is immediately usable
    export PATH="$HOME/.local/bin:$PATH"

    if command -v pipx &>/dev/null; then
        success "pipx installed successfully."
    else
        error "pipx installation failed."
        exit 1
    fi
fi

echo ""

# ── Step 6: Install Uni Watch ─────────────────
info "Installing Uni Watch via pipx..."

if pipx list 2>/dev/null | grep -q "uni-watch"; then
    warn "Uni Watch is already installed. Upgrading to latest version..."
    pipx upgrade uni-watch || true
else
    pipx install uni-watch
fi

success "Uni Watch is ready."
echo ""

# ── Step 7: Launch ────────────────────────────
line
success "Setup complete! Launching Uni Watch..."
line
echo ""

uni-watch

echo ""
line
info "Uni Watch has exited. Run it again anytime with: uni-watch"
line
