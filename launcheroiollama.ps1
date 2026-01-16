# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
$BasePath = "$env:USERPROFILE\.oi_launcher_simple"
$VenvPath = "$BasePath\venv"

# Ustawienie modelu (możesz tu wpisać gpt-4o, gpt-3.5-turbo itp.)
$ModelName = "gpt-4o" 

# --- 1. NAJPIERW TWORZYMY KATALOG (Żeby było gdzie zapisać klucz) ---
if (-not (Test-Path $BasePath)) { 
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null 
}

# --- 2. LOGIKA KLUCZA (ZMODYFIKOWANA - PYTA O KLUCZ) ---
$ApiKey = $null

# A. Sprawdź, czy klucz jest już w zmiennej środowiskowej
if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
    Write-Host "Wykryto klucz API w sesji terminala." -ForegroundColor Gray
}
# B. Jeśli nie, poszukaj pliku .env w folderze instalacyjnym
elseif (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") {
            $ApiKey = $matches[1].Trim()
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "Wczytano klucz z pliku lokalnego." -ForegroundColor Gray
    }
}

# C. Jeśli nadal brak klucza - ZAPYTAJ UŻYTKOWNIKA
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`n--- KONFIGURACJA ---" -ForegroundColor Yellow
    Write-Host "Nie wykryto klucza API." -ForegroundColor Gray
    
    $InputKey = Read-Host "Wklej swój klucz OpenAI API (sk-...)"
    
    if ([string]::IsNullOrWhiteSpace($InputKey)) {
        Write-Error "Nie podano klucza. Skrypt zakończy działanie."
        exit
    }
    
    $ApiKey = $InputKey.Trim()
    
    # Zapisz klucz do pliku, żeby nie pytać następnym razem
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
    Write-Host "Klucz został zapisany w folderze $BasePath" -ForegroundColor Green
}

Write-Host "--- Inicjowanie Loadera Open Interpreter ---" -ForegroundColor Cyan

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
    winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    
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
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

# 4.