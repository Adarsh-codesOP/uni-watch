#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  Uni Watch — Installer Script (Linux / macOS)
#  Works when piped: curl -fsSL <url> | bash
#  Works when run directly: ./install.sh
# ─────────────────────────────────────────────

# Do NOT use set -e — we handle all errors manually for proper fallbacks
set +e

# ── Colours ───────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

line()    { echo -e "${CYAN}──────────────────────────────────────────────${RESET}"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $1"; }
success() { echo -e "${GREEN}[OK]${RESET}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
err()     { echo -e "${RED}[ERROR]${RESET} $1"; }
ask()     { echo -e "${YELLOW}[INPUT]${RESET} $1"; }

# ── stdin fix: when piped via curl | bash, /dev/tty is used for user input ──
read_input() {
    if [ -t 0 ]; then
        read -r "$1"
    else
        read -r "$1" < /dev/tty
    fi
}

# ── Add a dir to PATH for this session (no duplicates) ──
add_to_path() {
    local dir="$1"
    [ -z "$dir" ] && return
    [ -d "$dir" ] || return
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir:$PATH" ;;
    esac
}

# ── Permanently add dir to shell profile ──────
add_to_profile() {
    local dir="$1"
    [ -z "$dir" ] && return

    local export_line="export PATH=\"$dir:\$PATH\""

    # Detect which shell profiles exist and write to them
    for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            if ! grep -qF "$dir" "$profile" 2>/dev/null; then
                echo "" >> "$profile"
                echo "# Added by Uni Watch installer" >> "$profile"
                echo "$export_line" >> "$profile"
            fi
        fi
    done

    add_to_path "$dir"
    success "Permanently added to PATH: $dir"
}

# ── Check if a command exists ──────────────────
has_cmd() { command -v "$1" &>/dev/null; }

# ── Run python -m <module> safely ─────────────
py_module() {
    local python="$1"; shift
    "$python" -m "$@" 2>/dev/null
}

# ── Banner ────────────────────────────────────
clear 2>/dev/null || true
line
echo -e "${BOLD}         Uni Watch — Auto Installer${RESET}"
echo -e "         Sets up everything and launches the app"
line
echo ""

# ── Step 1: Detect OS ─────────────────────────
info "Detecting operating system..."

OS=""
DISTRO=""
PKG_MANAGER=""

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    success "System detected: macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
    OS="linux"
    if [ -f /etc/os-release ]; then
        # Use a subshell to avoid polluting environment with os-release vars
        DISTRO=$(bash -c 'source /etc/os-release 2>/dev/null && echo "${ID:-unknown}"')
        DISTRO_LIKE=$(bash -c 'source /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}"')
        success "System detected: Linux ($DISTRO)"
    else
        DISTRO="unknown"
        success "System detected: Linux (unknown distro)"
    fi

    # Detect package manager
    if   has_cmd apt-get; then PKG_MANAGER="apt"
    elif has_cmd dnf;     then PKG_MANAGER="dnf"
    elif has_cmd yum;     then PKG_MANAGER="yum"
    elif has_cmd pacman;  then PKG_MANAGER="pacman"
    elif has_cmd zypper;  then PKG_MANAGER="zypper"
    fi
else
    err "Unsupported OS: $OSTYPE"
    err "This script supports Linux and macOS only."
    exit 1
fi

echo ""

# ── Step 2: Detect Python ─────────────────────
info "Checking for Python 3.9+..."

PYTHON_CMD=""
PYTHON_OK=false

# Search all common python binary names
for cmd in python3.13 python3.12 python3.11 python3.10 python3.9 python3 python; do
    if has_cmd "$cmd"; then
        version_out=$("$cmd" --version 2>&1)
        version=$(echo "$version_out" | awk '{print $2}')
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)

        # Validate numeric
        if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]]; then
            if [[ "$major" -ge 3 && "$minor" -ge 9 ]]; then
                PYTHON_CMD="$cmd"
                PYTHON_OK=true
                success "Python $version found at: $(command -v "$cmd")"
                break
            else
                warn "Python $version found but 3.9+ is required — skipping."
            fi
        fi
    fi
done

# Fallback: search common install paths
if [ "$PYTHON_OK" = false ]; then
    info "Searching common Python install locations..."
    for search_path in \
        /usr/bin/python3* \
        /usr/local/bin/python3* \
        /opt/homebrew/bin/python3* \
        /home/linuxbrew/.linuxbrew/bin/python3* \
        "$HOME/.pyenv/shims/python3" \
        "$HOME/.asdf/shims/python3"
    do
        for candidate in $search_path; do
            [ -x "$candidate" ] || continue
            version_out=$("$candidate" --version 2>&1)
            version=$(echo "$version_out" | awk '{print $2}')
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]]; then
                if [[ "$major" -ge 3 && "$minor" -ge 9 ]]; then
                    PYTHON_CMD="$candidate"
                    PYTHON_OK=true
                    success "Python $version found at: $candidate (fallback)"
                    add_to_path "$(dirname "$candidate")"
                    break 2
                fi
            fi
        done
    done
fi

echo ""

# ── Step 3: Install Python if missing ─────────
if [ "$PYTHON_OK" = false ]; then
    warn "Python 3.9+ was not found on your system."
    echo ""
    ask "Would you like this script to install Python for you? (yes/no)"
    read_input user_choice
    echo ""

    if [[ "$user_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        info "Installing Python 3..."

        install_ok=false

        if [[ "$OS" == "macos" ]]; then
            if ! has_cmd brew; then
                info "Homebrew not found. Installing Homebrew first..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
                # Apple Silicon path
                [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
                # Intel path
                [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
                success "Homebrew installed."
            fi
            brew install python@3.11 && install_ok=true
            add_to_path "$(brew --prefix python@3.11)/bin" 2>/dev/null || true
            PYTHON_CMD="python3"

        elif [[ "$OS" == "linux" ]]; then
            case "$PKG_MANAGER" in
                apt)
                    sudo apt-get update -qq && \
                    sudo apt-get install -y python3 python3-pip python3-venv && \
                    install_ok=true
                    ;;
                dnf)
                    sudo dnf install -y python3 python3-pip && install_ok=true
                    ;;
                yum)
                    sudo yum install -y python3 python3-pip && install_ok=true
                    ;;
                pacman)
                    sudo pacman -Sy --noconfirm python python-pip && install_ok=true
                    ;;
                zypper)
                    sudo zypper install -y python3 python3-pip && install_ok=true
                    ;;
                *)
                    err "No supported package manager found (tried apt, dnf, yum, pacman, zypper)."
                    err "Please install Python 3.9+ manually: https://www.python.org/downloads/"
                    err "Then re-run this script."
                    exit 1
                    ;;
            esac
            PYTHON_CMD="python3"
        fi

        if [ "$install_ok" = true ] && has_cmd "$PYTHON_CMD"; then
            version=$("$PYTHON_CMD" --version 2>&1)
            success "Python installed: $version"
            PYTHON_OK=true
        else
            err "Python installation failed."
            err "Please install Python 3.9+ manually: https://www.python.org/downloads/"
            exit 1
        fi

    else
        echo ""
        warn "Python installation skipped."
        info  "Install Python 3.9+ from: https://www.python.org/downloads/"
        info  "Then re-run this script."
        echo ""
        exit 0
    fi
fi

echo ""

# ── Step 4: Ensure pip ────────────────────────
info "Checking pip..."

PIP_OK=false

# Try direct pip commands first
for pip_cmd in pip3 pip "pip$(echo "$PYTHON_CMD" | grep -o '[0-9.]*$')"; do
    if has_cmd "$pip_cmd"; then
        out=$("$pip_cmd" --version 2>&1)
        if [[ "$out" == pip* ]]; then
            PIP_OK=true
            success "pip found: $pip_cmd"
            break
        fi
    fi
done

# Try python -m pip
if [ "$PIP_OK" = false ]; then
    out=$(py_module "$PYTHON_CMD" pip --version 2>&1)
    if [[ "$out" == pip* ]]; then
        PIP_OK=true
        success "pip available via: $PYTHON_CMD -m pip"
    fi
fi

# Bootstrap pip
if [ "$PIP_OK" = false ]; then
    warn "pip not found — bootstrapping..."

    # Try ensurepip first (built into Python 3.4+)
    if py_module "$PYTHON_CMD" ensurepip --upgrade &>/dev/null; then
        success "pip bootstrapped via ensurepip."
        PIP_OK=true
    else
        # Download get-pip.py
        info "Downloading get-pip.py..."
        if has_cmd curl; then
            curl -fsSL https://bootstrap.pypa.io/get-pip.py | "$PYTHON_CMD" && PIP_OK=true
        elif has_cmd wget; then
            wget -qO- https://bootstrap.pypa.io/get-pip.py | "$PYTHON_CMD" && PIP_OK=true
        else
            err "Neither curl nor wget found. Cannot install pip."
            err "Please install pip manually then re-run."
            exit 1
        fi
    fi

    if [ "$PIP_OK" = true ]; then
        success "pip installed."
        # Add user Scripts dir to PATH in case pip installed there
        add_to_path "$HOME/.local/bin"
    else
        err "Could not install pip. Please install manually."
        exit 1
    fi
fi

echo ""

# ── Step 5: Install pipx ──────────────────────
info "Installing pipx..."

PIPX_CMD=""
PIPX_OK=false

# Check if pipx already exists
for cmd in pipx "$HOME/.local/bin/pipx"; do
    if has_cmd "$cmd" || [ -x "$cmd" ]; then
        PIPX_CMD="$cmd"
        PIPX_OK=true
        success "pipx already installed: $($cmd --version 2>/dev/null || echo 'version unknown')"
        break
    fi
done

if [ "$PIPX_OK" = false ]; then
    # Install pipx via pip, with fallbacks
    install_pipx_ok=false

    py_module "$PYTHON_CMD" pip install --quiet --user --upgrade pipx 2>/dev/null && \
        install_pipx_ok=true

    if [ "$install_pipx_ok" = false ]; then
        py_module "$PYTHON_CMD" pip install --quiet --upgrade pipx 2>/dev/null && \
            install_pipx_ok=true
    fi

    if [ "$install_pipx_ok" = false ]; then
        err "Failed to install pipx."
        err "Please run: pip install pipx"
        exit 1
    fi

    # Reload PATH
    add_to_path "$HOME/.local/bin"

    # Run ensurepath
    if has_cmd pipx; then
        pipx ensurepath 2>/dev/null || true
        PIPX_CMD="pipx"
        PIPX_OK=true
    elif py_module "$PYTHON_CMD" pipx --version &>/dev/null; then
        py_module "$PYTHON_CMD" pipx ensurepath 2>/dev/null || true
        # Use module form as fallback command
        PIPX_CMD="$PYTHON_CMD -m pipx"
        PIPX_OK=true
    else
        err "pipx installed but cannot be invoked."
        err "Please open a new terminal and run: pipx install uni-watch"
        exit 1
    fi

    add_to_path "$HOME/.local/bin"
    success "pipx installed successfully."
fi

# Wrapper so we can call pipx regardless of its invocation form
run_pipx() {
    if [ "$PIPX_CMD" = "$PYTHON_CMD -m pipx" ]; then
        "$PYTHON_CMD" -m pipx "$@"
    else
        $PIPX_CMD "$@"
    fi
}

echo ""

# ── Step 6: Install Uni Watch ─────────────────
info "Installing Uni Watch via pipx..."

if run_pipx list 2>/dev/null | grep -q "uni-watch"; then
    warn "Already installed — upgrading to latest..."
    run_pipx upgrade uni-watch 2>/dev/null || true
    success "Uni Watch upgraded."
else
    if run_pipx install uni-watch; then
        success "Uni Watch installed."
    else
        err "Failed to install Uni Watch via pipx."
        err "Try manually: pipx install uni-watch"
        exit 1
    fi
fi

echo ""

# ── Step 7: Add uni-watch to PATH permanently ─
info "Locating uni-watch and adding to PATH..."

UNI_EXE=""

# Check all likely bin dirs
for bin_dir in \
    "$HOME/.local/bin" \
    "$HOME/.pipx/bin" \
    "$(run_pipx environment 2>/dev/null | grep PIPX_BIN_DIR | cut -d= -f2 | tr -d ' ')"
do
    [ -z "$bin_dir" ] && continue
    candidate="$bin_dir/uni-watch"
    if [ -x "$candidate" ]; then
        UNI_EXE="$candidate"
        add_to_profile "$bin_dir"
        break
    fi
done

# Broad search fallback
if [ -z "$UNI_EXE" ]; then
    candidate=$(find "$HOME" -name "uni-watch" -type f -perm /111 2>/dev/null | head -1)
    if [ -n "$candidate" ]; then
        UNI_EXE="$candidate"
        add_to_profile "$(dirname "$candidate")"
    fi
fi

if [ -n "$UNI_EXE" ]; then
    success "uni-watch located: $UNI_EXE"
    success "uni-watch added to PATH permanently."
else
    warn "uni-watch not found in PATH yet — may need a new terminal."
fi

echo ""

# ── Step 8: Launch ────────────────────────────
line
success "Setup complete! Launching Uni Watch..."
line
echo ""

LAUNCHED=false

# Try direct path first
if [ -n "$UNI_EXE" ] && [ -x "$UNI_EXE" ]; then
    "$UNI_EXE" && LAUNCHED=true || LAUNCHED=false
fi

# Try PATH
if [ "$LAUNCHED" = false ] && has_cmd uni-watch; then
    uni-watch && LAUNCHED=true || LAUNCHED=false
fi

# Try python -m uni_watch
if [ "$LAUNCHED" = false ]; then
    if py_module "$PYTHON_CMD" uni_watch 2>/dev/null; then
        LAUNCHED=true
    fi
fi

if [ "$LAUNCHED" = false ]; then
    err "Could not launch uni-watch automatically."
    err "Please open a NEW terminal and run: uni-watch"
    err "(PATH changes take effect in new terminals)"
fi

echo ""
line
info "Done. Run uni-watch anytime in a new terminal."
line
