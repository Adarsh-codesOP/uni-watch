# Uni Watch

A beautiful, fast, API-driven CLI tool to automate video progress completion on your online portal.

---

## Features

- **API-Driven** – Completes hours of video in seconds using backend APIs
- **Parallel Processing** – Runs up to 3 lectures simultaneously
- **Smart Skip** – Skips already completed lectures automatically
- **Network Recovery** – Handles connection drops and resumes
- **Retry Failed** – Retry failed lectures
- **Course Selection** – Run all or selected courses
- **Summary Dashboard** – Shows stats after execution
- **Beautiful UI** – Built with `rich`
- **Secure** – No credentials stored

---

## Quick Install (Automated)

The fastest way to get started. These scripts automatically detect your system, install Python if needed, set up pipx, install Uni Watch, and launch it — all in one step.

### Windows (PowerShell)

**Option A — One-liner (easiest)**

Open PowerShell and paste this single command:

```powershell
iex (irm https://raw.githubusercontent.com/Adarsh-codesOP/uni-watch/main/install.ps1)
```



**Option B — Download and run the script**

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Or right-click `install.ps1` and select **"Run with PowerShell"**.

What it does:
- Detects your Windows version
- Checks for Python 3.9+ and installs it via winget (or downloads the installer) if missing
- Asks for your confirmation before installing anything
- Installs pipx, then installs Uni Watch
- Launches Uni Watch automatically

### Linux / macOS (Bash)

**Option A — One-liner (easiest)**

```bash
curl -fsSL https://raw.githubusercontent.com/Adarsh-codesOP/uni-watch/main/install.sh | bash
```



**Option B — Download and run the script**

```bash
chmod +x install.sh
./install.sh
```

What it does:
- Detects your OS and Linux distro (Ubuntu, Fedora, Arch, etc.)
- Checks for Python 3.9+ and installs it using your system package manager if missing
- Asks for your confirmation before installing anything
- Installs pipx, then installs Uni Watch
- Launches Uni Watch automatically

> **Note:** If Python is not installed, the script will ask before doing anything. You can always choose to install it yourself and re-run the script.

---

## Installation (Recommended — Using `pip` + Virtual Environment)

This is the best method for beginners to avoid conflicts and keep things clean.

### Step-by-Step Setup

**1. Install Python (if not installed)**

Download from: https://www.python.org/downloads/

During installation, check **"Add Python to PATH"**.

**2. Create a project folder**

```bash
mkdir uni-watch
cd uni-watch
```

**3. Create a virtual environment**

```bash
python -m venv venv
```

**4. Activate the virtual environment**

Windows:

```bash
venv\Scripts\activate
```

macOS / Linux:

```bash
source venv/bin/activate
```

You should now see `(venv)` in your terminal.

**5. Upgrade pip (recommended)**

```bash
pip install --upgrade pip
```

**6. Install Uni Watch**

```bash
pip install uni-watch
```

**7. Run the tool**

```bash
uni-watch
```

**8. (Optional) Run with logs**

```bash
uni-watch --log
```

### To run again later

```bash
cd uni-watch
venv\Scripts\activate      # Windows
source venv/bin/activate   # macOS / Linux

uni-watch
```

---

## Alternative — Using `pipx` (Global Install)

Use this if you want to run `uni-watch` from anywhere without managing a virtual environment manually.

**1. Install pipx**

```bash
pip install pipx
```

**2. Add pipx to PATH**

```bash
pipx ensurepath
```

Restart your terminal after this step.

**3. Install Uni Watch**

```bash
pipx install uni-watch
```

**4. Run**

```bash
uni-watch
```

---

## Alternative — Using `uv` (Fastest and Modern)

A faster alternative to pip/pipx.

**1. Install uv**

```bash
pip install uv
```

Or using the official method:

```bash
curl -Ls https://astral.sh/uv/install.sh | sh
```

**2. Verify installation**

```bash
uv --version
```

**3. Install Uni Watch**

```bash
uv tool install uni-watch
```

**4. Run**

```bash
uni-watch
```

---

## Usage

Normal run:

```bash
uni-watch
```

Enable API logs:

```bash
uni-watch --log
```

---

## Requirements

- Python 3.9 or higher
- Stable internet connection

---

## Disclaimer

This software is provided strictly for educational purposes only. The authors do not support violating platform Terms of Service.

By using this tool, you accept full responsibility for any consequences. The authors hold zero liability.

---

## Contributing

Pull requests are welcome.
