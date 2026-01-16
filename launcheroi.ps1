# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"

# Ustawienia Modelu (OpenAI)
$ModelName = "gpt-5.2-codex" 
# UWAGA: Jeśli ten model nie istnieje w Twoim API, zmień na swój"

# --- 1. INICJALIZACJA KATALOGU ---
# Najpierw tworzymy folder, żeby mieć gdzie zapisać ewentualny klucz
if (-not (Test-Path $BasePath)) { 
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null 
    Write-Host "Utworzono katalog roboczy: $BasePath" -ForegroundColor Gray
}

# --- 2. LOGIKA KLUCZA (INTERAKTYWNA) ---
$ApiKey = $null

# A. Sprawdź zmienną środowiskową
if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
}
# B. Sprawdź plik .env
elseif (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") {
            $ApiKey = $matches[1].Trim()
        }
    }
}

# C. Jeśli brak klucza - ZAPYTAJ UŻYTKOWNIKA (Interakcja)
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`n--- WYMAGANA KONFIGURACJA ---" -ForegroundColor Yellow
    Write-Host "Nie wykryto klucza API OpenAI." -ForegroundColor Gray
    Write-Host "Klucz zostanie zapisany lokalnie w $BasePath\.env i nie będziesz musiał go podawać ponownie." -ForegroundColor Gray
    
    $InputKey = Read-Host "Wklej swój klucz OpenAI API (sk-...)"
    
    if ([string]::IsNullOrWhiteSpace($InputKey)) {
        Write-Error "Nie podano klucza. Skrypt zakończy działanie."
        exit
    }
    
    $ApiKey = $InputKey.Trim()
    
    # Zapisz do pliku .env
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
    Write-Host "Klucz został zapisany." -ForegroundColor Green
}

# --- 3. ZAPISANIE SKRYPTU LOKALNIE (oi.ps1) ---
# Tworzy plik uruchomieniowy, aby w przyszłości nie musieć pobierać go z netu
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try {
        Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString()
        Write-Host "Zapisano lokalny starter: $LauncherFile" -ForegroundColor Cyan
        Write-Host "Następnym razem możesz uruchomić go wpisując: & '$LauncherFile'" -ForegroundColor Cyan
    } catch {
        Write-Host "Nie udało się zapisać lokalnej kopii skryptu (uruchomiono z potoku bez dostępu do źródła)." -ForegroundColor DarkGray
    }
}

Write-Host "--- Inicjowanie Loadera Open Interpreter ($ModelName) ---" -ForegroundColor Cyan

# --- FUNKCJA: Znajdź lub Zainstaluj Python 3.11 ---
function Get-Python311 {
    Write-Host "Weryfikacja środowiska Python 3.11..." -ForegroundColor Gray
    
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $test = py -3.11 --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "py -3.11" }
    }

    $stdPath = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    if (Test-Path $stdPath) { return $stdPath }

    Write-Host "Brak Pythona 3.11. Próba instalacji przez Winget..." -ForegroundColor Yellow
    # Dodano --accept-source-agreements dla pewności cichej instalacji
    winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    
    if (Test-Path $stdPath) { return $stdPath }
    
    # Check PATH fallback
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
    if (python --version 2>&1 | Select-String "3.11") { return "python" }

    return $null
}

# Pobranie interpretera
$PyCmd = Get-Python311

if (-not $PyCmd) {
    Write-Error "Nie udało się znaleźć ani zainstalować Pythona 3.11. Uruchom skrypt jako Administrator lub zainstaluj Python 3.11 ręcznie."
    exit
}

# --- KONFIGURACJA VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie środowiska wirtualnego (może to chwilę potrwać)..." -ForegroundColor Yellow
    
    if ($PyCmd -eq "py -3.11") {
        py -3.11 -m venv $VenvPath
    } else {
        & $PyCmd -m venv $VenvPath
    }
    
    Write-Host "Instalacja bibliotek..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

# --- URUCHOMIENIE ---
$env:OPENAI_API_KEY = $ApiKey
# Usuwamy API BASE, bo łączymy się do oficjalnego OpenAI
if ($env:OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE } 

Write-Host "--- Uruchamianie Modelu $ModelName ---" -ForegroundColor Green

try {
    # Uruchomienie Open Interpreter
    & "$VenvPath\Scripts\interpreter" `
        --model $ModelName `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
} catch {
    Write-Error "Wystąpił błąd krytyczny podczas działania."
    Write-Host "Spróbuj usunąć folder $BasePath i uruchomić ponownie." -ForegroundColor Red
}