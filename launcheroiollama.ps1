# --- KONFIGURACJA ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

# Nowy czysty folder roboczy
$BasePath = "$env:USERPROFILE\.oi_session_temp"
$VenvPath = "$BasePath\venv"

# --- 1. AGRESYWNE CZYSZCZENIE STARYCH ŚMIECI ---
# To jest kluczowe, żeby naprawić błąd "No module named venv"
$OldPaths = @("$env:USERPROFILE\.oi_gpt_codex", "$env:USERPROFILE\.oi_launcher_simple")
foreach ($path in $OldPaths) {
    if (Test-Path $path) {
        Write-Host "Usuwanie starego środowiska: $path" -ForegroundColor DarkGray
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 2. PRZYGOTOWANIE KATALOGU ROBOCZEGO ---
if (Test-Path $BasePath) { Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $BasePath | Out-Null

Write-Host "--- OPEN INTERPRETER (RAM SESSION) ---" -ForegroundColor Cyan

# --- 3. KLUCZ API ---
if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
} else {
    Write-Host "Klucz będzie przechowywany tylko w pamięci RAM." -ForegroundColor Gray
    $InputKey = Read-Host "Wklej klucz OpenAI API (sk-...)"
    if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }
    $ApiKey = $InputKey.Trim()
}
$env:OPENAI_API_KEY = $ApiKey

# --- 4. BLOK GŁÓWNY ---
try {
    # A. SZUKANIE PYTHONA (SYSTEMOWEGO)
    function Get-SystemPython {
        # Szukamy "py" launchera lub "python" w PATH, ale sprawdzamy czy to nie jest ten zepsuty ZIP
        if (Get-Command py -ErrorAction SilentlyContinue) {
            # Sprawdź czy to wersja 3.10+
            $ver = py -c "import sys; print(sys.version_info.major)" 2>$null
            if ($ver -eq "3") { return "py" }
        }
        if (Get-Command python -ErrorAction SilentlyContinue) {
            # Upewnij się, że ma moduł venv
            try { python -m venv --help > $null; return "python" } catch {}
        }
        return $null
    }

    $PyCmd = Get-SystemPython

    # B. INSTALACJA PRZEZ WINGET (JEŚLI BRAK)
    if (-not $PyCmd) {
        Write-Host "Nie znaleziono pełnego Pythona. Instalacja przez Winget..." -ForegroundColor Yellow
        winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
        
        # Odświeżenie PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $PyCmd = "python"
    }

    Write-Host "Używanie interpretera: $PyCmd" -ForegroundColor Green

    # C. TWORZENIE VENV
    Write-Host "Tworzenie środowiska wirtualnego..." -ForegroundColor Yellow
    & $PyCmd -m venv $VenvPath

    if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
        throw "Nie udało się utworzyć venv. Prawdopodobnie Python jest uszkodzony lub blokowany."
    }

    # D. INSTALACJA
    Write-Host "Instalacja pakietów..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet

    # E. URUCHOMIENIE
    Write-Host "--- START ---" -ForegroundColor Green
    Write-Host "Wpisz 'exit' aby zakończyć i usunąć wszystko." -ForegroundColor Gray
    
    # Uruchamiamy model gpt-4o (możesz zmienić w kodzie jeśli chcesz inny)
    & "$VenvPath\Scripts\interpreter" `
        --model gpt-4o `
        --context_window 128000 `
        --max_tokens 4096 `
        -y `
        --system_message "Jesteś asystentem. Wykonujesz polecenia w systemie Windows. ZAWSZE odpowiadaj w języku polskim."

} catch {
    Write-Error "Wystąpił błąd: $_"
    Write-Host "Szczegóły: Jeśli błąd dotyczy SSL/Connect, upewnij się że masz zainstalowany pełny Python." -ForegroundColor Red
} finally {
    # --- AUTO-DESTRUKCJA ---
    Write-Host "`n--- SPRZĄTANIE ---" -ForegroundColor Cyan
    $env:OPENAI_API_KEY = $null
    
    Write-Host "Czekam na zwolnienie plików..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    
    try {
        if (Test-Path $BasePath) {
            Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Środowisko usunięte." -ForegroundColor Green
        }
    } catch {
        Write-Host "Możesz ręcznie usunąć folder: $BasePath" -ForegroundColor Yellow
    }
}
