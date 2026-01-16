# --- KONFIGURACJA ---
$BasePath = "$env:USERPROFILE\.oi_launcher_clean"
$VenvPath = "$BasePath\venv"
# Ważne: usuwamy stary folder z poprzednich eksperymentów, który powoduje błędy
if (Test-Path "$env:USERPROFILE\.oi_gpt_codex") { 
    Remove-Item "$env:USERPROFILE\.oi_gpt_codex" -Recurse -Force -ErrorAction SilentlyContinue 
}

# --- 1. START (CZYSTY STÓŁ) ---
if (Test-Path $BasePath) { 
    Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue 
}
New-Item -ItemType Directory -Force -Path $BasePath | Out-Null

# --- 2. KLUCZ API (PYTANIE) ---
Write-Host "--- OPEN INTERPRETER (CLEAN SESSION) ---" -ForegroundColor Cyan
$ApiKey = $null

if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
} else {
    Write-Host "Nie wykryto klucza w systemie." -ForegroundColor Yellow
    $InputKey = Read-Host "Wklej klucz OpenAI API (sk-...)"
    if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }
    $ApiKey = $InputKey.Trim()
}

$env:OPENAI_API_KEY = $ApiKey
# Czyścimy ew. stare ustawienia OpenRoutera/Ollamy
if (Test-Path Env:\OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE }

# --- 3. BLOK GŁÓWNY (TRY...FINALLY) ---
try {
    Write-Host "`n--- PRZYGOTOWANIE ŚRODOWISKA ---" -ForegroundColor Cyan

    # A. SZUKANIE / INSTALACJA PYTHONA (Oficjalny = Stabilny)
    function Get-Python311 {
        # Sprawdzamy czy mamy Pythona 3.11 w wersji x64 (Ważne dla ARM!)
        $Check = { param($c) try { & $c -c "import platform; print(platform.machine())" 2>$null } catch {} }
        
        # 1. Sprawdź 'py' launcher
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $arch = & $Check -c "py -3.11"
            if ($arch -match "AMD64|x86_64") { return "py -3.11" }
        }

        # 2. Sprawdź typowe ścieżki
        $paths = @(
            "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
            "C:\Program Files\Python311\python.exe"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $arch = & $Check -c $p
                if ($arch -match "AMD64|x86_64") { return $p }
            }
        }

        return $null
    }

    $PyCmd = Get-Python311

    if (-not $PyCmd) {
        Write-Host "Nie znaleziono Pythona 3.11 (x64). Instalacja przez Winget..." -ForegroundColor Yellow
        # Instalujemy wersję x64, która zadziała wszędzie (nawet na Parallels/ARM przez emulację)
        winget install -e --id Python.Python.3.11 --architecture x64 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
        
        $PyCmd = Get-Python311
        if (-not $PyCmd) { throw "Nie udało się zainstalować Pythona 3.11." }
    }

    Write-Host "Używanie interpretera: $PyCmd" -ForegroundColor Green

    # B. TWORZENIE VENV
    Write-Host "Tworzenie środowiska wirtualnego..." -ForegroundColor Yellow
    
    if ($PyCmd -eq "py -3.11") {
        py -3.11 -m venv $VenvPath
    } else {
        & $PyCmd -m venv $VenvPath
    }

    if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
        throw "Błąd: Nie udało się utworzyć venv. Upewnij się, że Python jest poprawnie zainstalowany."
    }

    # C. INSTALACJA PAKIETÓW
    Write-Host "Instalacja Open Interpreter..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet

    # D. URUCHOMIENIE
    Write-Host "--- START GPT-4o ---" -ForegroundColor Green
    Write-Host "Wpisz 'exit' aby zakończyć i usunąć pliki." -ForegroundColor Gray
    
    & "$VenvPath\Scripts\interpreter" `
        --model gpt-4o `
        --context_window 128000 `
        --max_tokens 4096 `
        -y `
        --system_message "Jesteś asystentem. Wykonujesz polecenia w systemie Windows. ZAWSZE odpowiadaj w języku polskim."

} catch {
    Write-Error "Wystąpił błąd krytyczny: $_"
} finally {
    # --- AUTO-DESTRUKCJA ---
    Write-Host "`n--- CZYSZCZENIE PO ZAKOŃCZENIU ---" -ForegroundColor Cyan
    $env:OPENAI_API_KEY = $null
    
    Write-Host "Czekam na zamknięcie procesów..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    
    try {
        if (Test-Path $BasePath) {
            Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Pliki tymczasowe zostały usunięte." -ForegroundColor Green
        }
    } catch {
        Write-Host "Nie można usunąć folderu (coś go blokuje). Usuń ręcznie: $BasePath" -ForegroundColor Yellow
    }
}
