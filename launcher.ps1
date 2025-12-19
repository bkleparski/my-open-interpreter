# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
$BasePath = "$env:USERPROFILE\.oi_deepseek_launcher"
$VenvPath = "$BasePath\venv"
$ApiBase = "https://ollama.ebartnet.pl/v1"

# Ustalanie ścieżki do pliku .env (szuka w tym samym folderze co skrypt)
$EnvPath = "$PSScriptRoot\.env"
$ApiKey = $null

# Logika wczytywania klucza z pliku .env
if (Test-Path $EnvPath) {
    foreach ($line in Get-Content $EnvPath) {
        # Szuka linii wyglądającej jak: OPENAI_API_KEY=twoj_klucz
        if ($line -match "^OPENAI_API_KEY=(.*)$") {
            $ApiKey = $matches[1].Trim()
        }
    }
}

# Sprawdzenie bezpieczeństwa - jeśli klucza nie ma, zatrzymaj skrypt
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "BŁĄD KRYTYCZNY: Nie znaleziono klucza API!" -ForegroundColor Red
    Write-Host "1. Upewnij się, że plik .env istnieje w: $PSScriptRoot" -ForegroundColor Gray
    Write-Host "2. Upewnij się, że w pliku jest linia: OPENAI_API_KEY=sk-twoj-klucz" -ForegroundColor Gray
    Start-Sleep -Seconds 10
    exit
}

Write-Host "--- Inicjowanie Loadera Open Interpreter (Deepseek) ---" -ForegroundColor Cyan

# --- FUNKCJA: Znajdź lub Zainstaluj Python 3.11 ---
function Get-Python311 {
    Write-Host "Szukanie Pythona 3.11 (wymagany dla stabilności)..." -ForegroundColor Gray
    
    # 1. Sprawdź czy "py" launcher ma dostęp do 3.11
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $test = py -3.11 --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "py -3.11" }
    }

    # 2. Sprawdź standardową ścieżkę instalacji Winget/Local
    $stdPath = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    if (Test-Path $stdPath) { return $stdPath }

    # 3. Jeśli nie znaleziono - Instaluj
    Write-Host "Nie znaleziono Python 3.11. Instalacja wersji kompatybilnej..." -ForegroundColor Yellow
    winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements
    
    # Ponowne sprawdzenie po instalacji
    if (Test-Path $stdPath) { return $stdPath }
    
    # Ostatnia deska ratunku - sprawdź czy dodano do PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
    if (python --version | Select-String "3.11") { return "python" }

    return $null
}

# 1. Pobierz właściwy plik wykonywalny
$PyCmd = Get-Python311

if (-not $PyCmd) {
    Write-Error "Nie udało się znaleźć ani zainstalować Pythona 3.11. Odinstaluj ręcznie Pythona 3.13 i spróbuj ponownie."
    exit
}

Write-Host "Używanie interpretera: $PyCmd" -ForegroundColor Green

# 2. Tworzenie katalogu
if (-not (Test-Path $BasePath)) { New-Item -ItemType Directory -Force -Path $BasePath | Out-Null }

# 3. Tworzenie VENV (Używając konkretnie 3.11!)
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie środowiska wirtualnego..." -ForegroundColor Yellow
    
    # Wywołanie komendy tworzenia venv
    if ($PyCmd -eq "py -3.11") {
        py -3.11 -m venv $VenvPath
    } else {
        & $PyCmd -m venv $VenvPath
    }
    
    if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
        Write-Error "BŁĄD: Nie udało się utworzyć venv."
        exit
    }

    Write-Host "Instalacja Open Interpreter..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel
    & "$VenvPath\Scripts\pip" install open-interpreter
}

# 4. Uruchomienie (Klucz jest brany ze zmiennej wczytanej na górze skryptu)
$env:OPENAI_API_KEY = $ApiKey
$env:OPENAI_API_BASE = $ApiBase

Write-Host "--- Uruchamianie Modelu Deepseek (PL) ---" -ForegroundColor Green

try {
    & "$VenvPath\Scripts\interpreter" `
        --model openai/deepseek `
        --context_window 16000 `
        --max_tokens 4096 `
        -y `
        --system_message "Jesteś asystentem. Wykonujesz polecenia w systemie Windows. ZAWSZE odpowiadaj w języku polskim."
} catch {
    Write-Error "Wystąpił błąd krytyczny."
    Write-Host "Spróbuj usunąć folder $BasePath i uruchomić ponownie." -ForegroundColor Red
}