# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$LocalPythonDir = "$BasePath\python_bin"
$LocalPythonExe = "$LocalPythonDir\python.exe"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"

# --- ZMIANA MODELU NA NAJLEPSZY DOSTĘPNY (GPT-4o) ---
$ModelName = "gpt-4o" 

# --- 0. CZYSZCZENIE (Tylko jeśli venv jest uszkodzony) ---
if (Test-Path "$VenvPath") {
    if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
        Write-Host "Naprawa uszkodzonego środowiska..." -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 1. INICJALIZACJA KATALOGU ---
if (-not (Test-Path $BasePath)) { New-Item -ItemType Directory -Force -Path $BasePath | Out-Null }

# --- 2. ZAAWANSOWANA OBSŁUGA KLUCZA (FIX DLA VM) ---
Clear-Host
Write-Host "--- KONFIGURACJA KLUCZA OPENAI ---" -ForegroundColor Cyan

$ApiKey = $null
$Source = "Brak"

# A. Sprawdź plik .env
if (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") { 
            $ApiKey = $matches[1].Trim()
            $Source = "Plik lokalny"
        }
    }
}

# B. Sprawdź zmienne systemowe (częsty przypadek na VM)
if ([string]::IsNullOrWhiteSpace($ApiKey) -and -not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    $ApiKey = $env:OPENAI_API_KEY
    $Source = "System Windows (zmienna globalna)"
}

# C. INTERAKCJA - ZAWSZE PYTAJ JEŚLI KLUCZ ISTNIEJE
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $Masked = "sk-..." + $ApiKey.Substring($ApiKey.Length - 4)
    
    Write-Host "Znaleziono klucz w: $Source" -ForegroundColor Gray
    Write-Host "Klucz: $Masked" -ForegroundColor Green
    Write-Host "------------------------------------------------" -ForegroundColor Gray
    Write-Host "[ENTER]  -> Użyj tego klucza" -ForegroundColor White
    Write-Host "[zmien]  -> Wpisz nowy klucz" -ForegroundColor Yellow
    
    $UserDecision = Read-Host "Twój wybór"
    
    if ($UserDecision -match "zmien|nowy|reset") {
        $ApiKey = $null
        if (Test-Path "$BasePath\.env") { Remove-Item "$BasePath\.env" -Force }
        $env:OPENAI_API_KEY = $null # Czyścimy sesję
    }
}

# D. PROŚBA O KLUCZ (Jeśli brak lub reset)
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`nNie skonfigurowano klucza API." -ForegroundColor Yellow
    $InputKey = Read-Host "Wklej klucz OpenAI (zaczyna się od sk-...)"
    
    if ([string]::IsNullOrWhiteSpace($InputKey)) { 
        Write-Error "Nie podano klucza. Skrypt zakończy działanie."
        exit 
    }
    
    $ApiKey = $InputKey.Trim()
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
    Write-Host "Klucz zapisano bezpiecznie w folderze .oi_gpt_codex." -ForegroundColor Green
}

# Ustawienie klucza dla tej sesji
$env:OPENAI_API_KEY = $ApiKey
# Usunięcie starych override'ów
if (Test-Path Env:\OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE }


# --- 3. ZAPISANIE STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "`n--- Inicjowanie Open Interpreter (Model: $ModelName) ---" -ForegroundColor Cyan

# --- FUNKCJA: INSTALACJA PRYWATNEGO PYTHONA X64 ---
function Ensure-LocalPythonX64 {
    if (Test-Path $LocalPythonExe) { return $LocalPythonExe }

    Write-Host "Pobieranie Pythona 3.11 (x64) - wymagane do poprawnego działania..." -ForegroundColor Yellow
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

# --- KONFIGURACJA VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie środowiska..." -ForegroundColor Yellow
    & $PyCmd -m venv $VenvPath
    Write-Host "Instalacja Open Interpreter..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

Write-Host "--- START ---" -ForegroundColor Green

try {
    & "$VenvPath\Scripts\interpreter" `
        --model $ModelName `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
} catch {
    Write-Error "Błąd uruchomienia."
}
