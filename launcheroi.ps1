# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$LocalPythonDir = "$BasePath\python_bin"
$LocalPythonExe = "$LocalPythonDir\python.exe"
$LauncherFile = "$BasePath\oi.ps1"
$PyStartFile = "$BasePath\start_oi.py"

# --- 1. HIGIENA DANYCH ---
if (Test-Path "$BasePath\.env") { Remove-Item "$BasePath\.env" -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path $BasePath)) { New-Item -ItemType Directory -Force -Path $BasePath | Out-Null }

# --- 2. TRYB "RAM ONLY" (INCOGNITO) ---
Clear-Host
Write-Host "--- OPEN INTERPRETER (2026 EDITION) ---" -ForegroundColor Cyan
Write-Host "Tryb incognito: Klucze tylko w RAM." -ForegroundColor Gray
Write-Host "------------------------------------------------" -ForegroundColor DarkGray

Write-Host "Wybierz dostawcę:" -ForegroundColor Cyan
Write-Host "[1] OpenAI" -ForegroundColor White
Write-Host "[2] OpenRouter" -ForegroundColor White

$ProvSel = Read-Host "Wybór"

# Zmienne sterujące
$UseOpenRouter = $false

if ($ProvSel -eq "2") {
    $UseOpenRouter = $true
    Write-Host "Podaj model (slug z OpenRouter, np. 'anthropic/claude-3.5-sonnet'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "anthropic/claude-3.5-sonnet" }
    
    # --- FIX: NATIVE OPENROUTER SUPPORT ---
    # Używamy natywnego przedrostka 'openrouter/', który LiteLLM rozumie bezbłędnie.
    # Nie ustawiamy API_BASE ręcznie, LiteLLM zrobi to sam.
    if ($RawModel -match "^openrouter/") {
        $CurrentModel = $RawModel
    } else {
        $CurrentModel = "openrouter/$RawModel"
    }
} else {
    Write-Host "Podaj model (np. 'gpt-4o'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "gpt-4o" }
    $CurrentModel = $RawModel
}

Write-Host "Wklej klucz API (Będzie widoczny jako *****):" -ForegroundColor Yellow
try {
    $SecureKey = Read-Host "Klucz" -AsSecureString
    $InputKey = [System.Net.NetworkCredential]::new("", $SecureKey).Password
} catch {
    $InputKey = ""
}

if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }

# --- KONFIGURACJA ZMIENNYCH ŚRODOWISKOWYCH ---
# Czyścimy stare śmieci
if (Test-Path Env:\OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue }
if (Test-Path Env:\OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }

if ($UseOpenRouter) {
    # Dla OpenRouter ustawiamy klucz w dwóch miejscach dla pewności
    $env:OPENROUTER_API_KEY = $InputKey
    $env:OPENAI_API_KEY = $InputKey
    # WAŻNE: Nie ustawiamy OPENAI_API_BASE, bo przedrostek "openrouter/" w modelu sam to załatwia
} else {
    # Standardowe OpenAI
    $env:OPENAI_API_KEY = $InputKey
}

# --- 3. ZAPIS STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "`n--- Inicjowanie środowiska (Metoda Portable ZIP) ---" -ForegroundColor Cyan

# --- 4. INSTALACJA PYTHON (METODA ZIP) ---
function Ensure-LocalPythonZIP {
    if (Test-Path $LocalPythonExe) { return $LocalPythonExe }
    
    # Reset folderu jeśli brak exe
    if (Test-Path $LocalPythonDir) { Remove-Item $LocalPythonDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $LocalPythonDir | Out-Null

    Write-Host "Pobieranie Python 3.11 (Embedded ZIP x64)..." -ForegroundColor Yellow
    $ZipUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
    $ZipPath = "$BasePath\python.zip"
    
    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
        Write-Host "Rozpakowywanie..." -ForegroundColor Yellow
        Expand-Archive -Path $ZipPath -DestinationPath $LocalPythonDir -Force
        Remove-Item $ZipPath -ErrorAction SilentlyContinue

        $PthFile = "$LocalPythonDir\python311._pth"
        if (Test-Path $PthFile) {
            $Content = Get-Content $PthFile
            $Content = $Content -replace "#import site", "import site"
            Set-Content -Path $PthFile -Value $Content
        }

        Write-Host "Instalacja PIP..." -ForegroundColor Yellow
        $GetPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $GetPipPath = "$LocalPythonDir\get-pip.py"
        Invoke-WebRequest -Uri $GetPipUrl -OutFile $GetPipPath
        
        & "$LocalPythonExe" "$GetPipPath" --no-warn-script-location | Out-Null
        Remove-Item $GetPipPath -ErrorAction SilentlyContinue
        return $LocalPythonExe
    } catch {
        Write-Error "Błąd instalacji: $_"
        exit
    }
}

$PyCmd = Ensure-LocalPythonZIP

# --- 5. INSTALACJA OPEN INTERPRETER ---
Write-Host "Weryfikacja bibliotek..." -ForegroundColor Yellow
& "$PyCmd" -m pip install --upgrade pip setuptools wheel --no-warn-script-location --quiet
& "$PyCmd" -m pip install open-interpreter --no-warn-script-location --quiet

# --- 6. PLIK STARTOWY (DIRECT PYTHON) ---
$PythonLaunchCode = @"
import sys
import os

# Wymuszenie UTF-8
sys.stdout.reconfigure(encoding='utf-8')

def start():
    print(f"Uruchamianie loadera...")
    try:
        from interpreter.terminal_interface.start_terminal_interface import main
        # Argumenty są przekazywane automatycznie przez sys.argv
        main()
    except Exception as e:
        print(f"\nCRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        input('\nWcisnij ENTER aby zamknac...')

if __name__ == "__main__":
    start()
"@

Set-Content -Path $PyStartFile -Value $PythonLaunchCode

Write-Host "--- START: $CurrentModel ---" -ForegroundColor Green

try {
    # Uruchomienie
    & "$PyCmd" "$PyStartFile" `
        --model $CurrentModel `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
} catch {
    Write-Error "Błąd uruchomienia: $_"
} finally {
    $env:OPENAI_API_KEY = $null
    $env:OPENROUTER_API_KEY = $null
    $env:OPENAI_API_BASE = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
