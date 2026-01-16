# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$LocalPythonDir = "$BasePath\python_bin"
$LocalPythonExe = "$LocalPythonDir\python.exe"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"

# --- 1. HIGIENA DANYCH (CZYŚCIMY ŚLADY) ---
# Jeśli istnieje stary plik z kluczem, usuwamy go dla bezpieczeństwa
if (Test-Path "$BasePath\.env") {
    Write-Host "Wykryto stary plik konfiguracyjny. Usuwanie dla bezpieczeństwa..." -ForegroundColor DarkGray
    Remove-Item "$BasePath\.env" -Force
}

# Inicjalizacja folderu (tylko dla bibliotek)
if (-not (Test-Path $BasePath)) { New-Item -ItemType Directory -Force -Path $BasePath | Out-Null }

# --- 2. TRYB "RAM ONLY" - KONFIGURACJA SESJI ---
Clear-Host
Write-Host "--- OPEN INTERPRETER (TRYB INCOGNITO) ---" -ForegroundColor Cyan
Write-Host "Klucz i ustawienia zostaną usunięte z pamięci natychmiast po zakończeniu pracy." -ForegroundColor Gray
Write-Host "------------------------------------------------" -ForegroundColor DarkGray

# Wybór dostawcy (Szybkie menu)
Write-Host "Wybierz dostawcę:" -ForegroundColor Cyan
Write-Host "[1] OpenAI" -ForegroundColor White
Write-Host "[2] OpenRouter" -ForegroundColor White

$ProvSel = Read-Host "Wybór"

if ($ProvSel -eq "2") {
    $CurrentBase = "https://openrouter.ai/api/v1"
    Write-Host "Podaj model (np. 'anthropic/claude-3.5-sonnet'):" -ForegroundColor Yellow
    $CurrentModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($CurrentModel)) { $CurrentModel = "anthropic/claude-3.5-sonnet" }
} else {
    $CurrentBase = $null
    Write-Host "Podaj model (np. 'gpt-4o'):" -ForegroundColor Yellow
    $CurrentModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($CurrentModel)) { $CurrentModel = "gpt-4o" }
}

# Pobranie klucza do RAM
Write-Host "Wklej klucz API (nie zostanie zapisany):" -ForegroundColor Yellow
$InputKey = Read-Host "Klucz (sk-...)"

if ([string]::IsNullOrWhiteSpace($InputKey)) {
    Write-Error "Bez klucza nie ruszę. Zamykanie."
    exit
}

# Ustawienie zmiennych środowiskowych TYLKO dla tego procesu
$env:OPENAI_API_KEY = $InputKey.Trim()
if ($CurrentBase) { $env:OPENAI_API_BASE = $CurrentBase } else { Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue }

# --- 3. ZAPISANIE STARTERA (Dla wygody uruchamiania, ale BEZ KLUCZA) ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "`n--- Inicjowanie środowiska (Izolacja x64) ---" -ForegroundColor Cyan

# --- 4. SILNIK PYTHON x64 ---
function Ensure-LocalPythonX64 {
    if (Test-Path $LocalPythonExe) { return $LocalPythonExe }

    Write-Host "Pobieranie Pythona 3.11 (x64)..." -ForegroundColor Yellow
    $InstallerUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $InstallerPath = "$BasePath\python_installer.exe"
    
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath
        Write-Host "Instalacja silnika Python..." -ForegroundColor Yellow
        $args = "/quiet InstallAllUsers=0 TargetDir=`"$LocalPythonDir`" PrependPath=0 Include_test=0 Shortcuts=0"
        Start-Process -FilePath $InstallerPath -ArgumentList $args -Wait
        Remove-Item $InstallerPath -ErrorAction SilentlyContinue
        return $LocalPythonExe
    } catch {
        Write-Error "Błąd instalacji Pythona."
        exit
    }
}

$PyCmd = Ensure-LocalPythonX64

# --- 5. START VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie wirtualnego środowiska..." -ForegroundColor Yellow
    & $PyCmd -m venv $VenvPath
    Write-Host "Instalacja Open Interpreter..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

Write-Host "--- START: $CurrentModel ---" -ForegroundColor Green

try {
    # Uruchomienie
    & "$VenvPath\Scripts\interpreter" `
        --model $CurrentModel `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
} catch {
    Write-Error "Błąd uruchomienia."
} finally {
    # --- BEZPIECZNIK ---
    # Po zakończeniu programu (lub błędzie) zerujemy klucz w pamięci
    $env:OPENAI_API_KEY = $null
    $env:OPENAI_API_BASE = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
