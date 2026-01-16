# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"
$ModelName = "gpt-5.2-codex" # Zmień na gpt-4o w razie potrzeby

# --- 0. DIAGNOSTYKA I CZYSZCZENIE (Fix dla ARM) ---
# Jeśli venv istnieje, sprawdzamy czy działa. Jeśli nie (bo był ARM) - usuwamy.
if (Test-Path "$VenvPath\Scripts\python.exe") {
    try {
        & "$VenvPath\Scripts\python" -c "import fastuuid" 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Broken" }
    } catch {
        Write-Host "Wykryto uszkodzone środowisko (poprzednia zła architektura). Usuwanie..." -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 1. INICJALIZACJA KATALOGU ---
if (-not (Test-Path $BasePath)) { 
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null 
}

# --- 2. LOGIKA KLUCZA ---
$ApiKey = $null
if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) { $ApiKey = $env:OPENAI_API_KEY }
elseif (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") { $ApiKey = $matches[1].Trim() }
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`n--- KONFIGURACJA ---" -ForegroundColor Yellow
    $InputKey = Read-Host "Wklej klucz OpenAI API (sk-...)"
    if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }
    $ApiKey = $InputKey.Trim()
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
}

# --- 3. ZAPISANIE STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "--- Inicjowanie Loadera Open Interpreter (x64 Force) ---" -ForegroundColor Cyan

# --- FUNKCJA: Znajdź lub Zainstaluj Python 3.11 (x64) ---
function Get-Python311-X64 {
    # Funkcja sprawdzająca architekturę pliku wykonywalnego
    $CheckArch = { param($cmd) 
        try {
            $arch = & $cmd -c "import platform; print(platform.machine())" 2>$null
            if ($arch -match "AMD64|x86_64") { return $true } # Tylko x64 jest OK
        } catch { return $false }
        return $false
    }

    # 1. Sprawdź istniejące instalacje
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Program Files\Python311\python.exe",
        "C:\Python311\python.exe"
    )
    
    # Sprawdź 'py' launcher
    if (Get-Command py -ErrorAction SilentlyContinue) {
        if ((py -3.11-64 --version 2>&1) -match "3.11") { return "py -3.11-64" }
    }

    foreach ($p in $paths) {
        if (Test-Path $p) { if (& $CheckArch -cmd $p) { return $p } }
    }

    # 2. INSTALACJA (Jeśli nie znaleziono)
    Write-Host "Nie znaleziono Pythona 3.11 (x64). Rozpoczynam instalację..." -ForegroundColor Yellow
    
    # Metoda A: Winget (Preferowana)
    try {
        Write-Host "Próba instalacji przez Winget..." -ForegroundColor Gray
        winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    } catch {
        Write-Host "Winget nie zadziałał." -ForegroundColor DarkGray
    }

    # Sprawdzenie po Winget
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }

    # Metoda B: Bezpośrednie pobieranie (Fallback dla VM bez Winget)
    Write-Host "Pobieranie instalatora Python 3.11 z python.org..." -ForegroundColor Yellow
    $InstallerPath = "$BasePath\python_installer.exe"
    try {
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile $InstallerPath
        Write-Host "Instalowanie Pythona..." -ForegroundColor Yellow
        # Cicha instalacja do standardowego folderu użytkownika
        Start-Process -FilePath $InstallerPath -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0" -Wait
        Remove-Item $InstallerPath -ErrorAction SilentlyContinue
    } catch {
        Write-Error "Nie udało się pobrać lub zainstalować Pythona."
        exit
    }

    # Ostateczne sprawdzenie
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    
    # Sprawdzenie PATH
    if (Get-Command python -ErrorAction SilentlyContinue) {
        if (& $CheckArch -cmd "python") { return "python" }
    }

    return $null
}

$PyCmd = Get-Python311-X64

if (-not $PyCmd) {
    Write-Error "KRYTYCZNY BŁĄD: Nie udało się zapewnić środowiska Python 3.11 x64."
    exit
}

Write-Host "Używanie interpretera: $PyCmd" -ForegroundColor Green

# --- KONFIGURACJA VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie venv..." -ForegroundColor Yellow
    if ($PyCmd -eq "py -3.11-64") { py -3.11-64 -m venv $VenvPath } else { & $PyCmd -m venv $VenvPath }
    
    Write-Host "Instalacja pakietów..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

# --- URUCHOMIENIE ---
$env:OPENAI_API_KEY = $ApiKey
if ($env:OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE } 

Write-Host "--- START: $ModelName ---" -ForegroundColor Green

try {
    & "$VenvPath\Scripts\interpreter" `
        --model $ModelName `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w Windows. Odpowiadaj zwięźle po polsku."
} catch {
    Write-Error "Błąd uruchomienia."
}
