# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"
$ModelName = "gpt-5.2-codex" # Zmień na gpt-4o jeśli nie masz dostępu do customowego modelu

# --- 0. CZYSZCZENIE PO BŁĘDACH (FIX dla win-arm64) ---
# Jeśli venv istnieje, ale instalacja wcześniej padła, musimy go usunąć, 
# bo może być stworzony pod złą architekturę (ARM zamiast x64).
if (Test-Path "$VenvPath") {
    # Sprawdzamy czy pip działa, jeśli nie - usuwamy venv
    try {
        & "$VenvPath\Scripts\python" -c "import fastuuid" 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Broken install" }
    } catch {
        Write-Host "Wykryto uszkodzone środowisko (poprzedni błąd). Czyszczenie..." -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 1. INICJALIZACJA KATALOGU ---
if (-not (Test-Path $BasePath)) { 
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null 
    Write-Host "Utworzono katalog roboczy: $BasePath" -ForegroundColor Gray
}

# --- 2. LOGIKA KLUCZA (INTERAKTYWNA) ---
$ApiKey = $null

if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
}
elseif (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") {
            $ApiKey = $matches[1].Trim()
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`n--- WYMAGANA KONFIGURACJA ---" -ForegroundColor Yellow
    Write-Host "Nie wykryto klucza API OpenAI." -ForegroundColor Gray
    
    $InputKey = Read-Host "Wklej swój klucz OpenAI API (sk-...)"
    
    if ([string]::IsNullOrWhiteSpace($InputKey)) {
        Write-Error "Nie podano klucza. Skrypt zakończy działanie."
        exit
    }
    
    $ApiKey = $InputKey.Trim()
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
    Write-Host "Klucz został zapisany." -ForegroundColor Green
}

# --- 3. ZAPISANIE SKRYPTU LOKALNIE ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try {
        Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString()
        Write-Host "Zapisano lokalny starter: $LauncherFile" -ForegroundColor Cyan
    } catch { }
}

Write-Host "--- Inicjowanie Loadera Open Interpreter ($ModelName) ---" -ForegroundColor Cyan

# --- FUNKCJA: Znajdź Pythona 3.11 (TYLKO x64!) ---
function Get-Python311-X64 {
    Write-Host "Szukanie Pythona 3.11 w architekturze x64 (wymagane dla bibliotek)..." -ForegroundColor Gray
    
    # Helper do sprawdzania architektury
    $CheckArch = { param($cmd) 
        try {
            $arch = & $cmd -c "import platform; print(platform.machine())" 2>$null
            # Akceptujemy AMD64 lub x86_64. Odrzucamy ARM64.
            if ($arch -match "AMD64|x86_64") { return $true }
        } catch { return $false }
        return $false
    }

    # 1. Sprawdź 'py' launcher
    if (Get-Command py -ErrorAction SilentlyContinue) {
        # Wymuszamy wersję 3.11-64bit
        $test = py -3.11-64 --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "py -3.11-64" }
    }

    # 2. Sprawdź standardową ścieżkę instalacji x64
    # Na Windows ARM, programy x64 też lądują w Program Files, ale sprawdzamy obie
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Program Files\Python311\python.exe"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) {
            if (& $CheckArch -cmd $p) { return $p }
        }
    }

    # 3. Jeśli nie znaleziono x64 - Instaluj przez Winget
    Write-Host "Nie znaleziono Pythona 3.11 (x64). Instalacja..." -ForegroundColor Yellow
    
    # Kluczowe: --architecture x64
    winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    
    # Ponowne sprawdzenie
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    
    # Ostateczność: Sprawdź PATH, ale zweryfikuj czy to nie ARM
    if (Get-Command python -ErrorAction SilentlyContinue) {
        if (& $CheckArch -cmd "python") {
            if (python --version | Select-String "3.11") { return "python" }
        }
    }

    return $null
}

$PyCmd = Get-Python311-X64

if (-not $PyCmd) {
    Write-Error "Nie udało się znaleźć Pythona 3.11 w wersji x64."
    Write-Host "Na komputerach ARM (Surface/Mac) musisz zainstalować wersję 'Windows x86-64 executable installer' ze strony python.org." -ForegroundColor Red
    exit
}

Write-Host "Używanie interpretera: $PyCmd" -ForegroundColor Green

# --- KONFIGURACJA VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie środowiska wirtualnego..." -ForegroundColor Yellow
    
    if ($PyCmd -eq "py -3.11-64") {
        py -3.11-64 -m venv $VenvPath
    } else {
        & $PyCmd -m venv $VenvPath
    }
    
    Write-Host "Instalacja Open Interpreter..." -ForegroundColor Yellow
    # Aktualizacja pip jest kluczowa dla binarek x64
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

# --- URUCHOMIENIE ---
$env:OPENAI_API_KEY = $ApiKey
if ($env:OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE } 

Write-Host "--- Uruchamianie Modelu $ModelName ---" -ForegroundColor Green

try {
    & "$VenvPath\Scripts\interpreter" `
        --model $ModelName `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
} catch {
    Write-Error "Wystąpił błąd krytyczny."
    Write-Host "Spróbuj usunąć folder $BasePath i uruchomić ponownie." -ForegroundColor Red
}
