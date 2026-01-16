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

if ($ProvSel -eq "2") {
    $CurrentBase = "https://openrouter.ai/api/v1"
    Write-Host "Podaj model (np. 'anthropic/claude-sonnet-4.5'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "anthropic/claude-sonnet-4.5" }
    
    # --- CRITICAL FIX DLA OPENROUTER ---
    # Jeśli model to np. "anthropic/...", LiteLLM próbuje łączyć się z Anthropic bezpośrednio.
    # Musimy wymusić protokół OpenAI, dodając przedrostek "openai/", żeby użył naszego API BASE.
    if ($RawModel -notmatch "^openai/") {
        $CurrentModel = "openai/$RawModel"
    } else {
        $CurrentModel = $RawModel
    }
} else {
    $CurrentBase = $null
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

$env:OPENAI_API_KEY = $InputKey
if ($CurrentBase) { $env:OPENAI_API_BASE = $CurrentBase } else { Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue }

# --- 3. ZAPIS STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "`n--- Inicjowanie środowiska (Metoda Portable ZIP) ---" -ForegroundColor Cyan

# --- 4. INSTALACJA PYTHON (METODA ZIP) ---
function Ensure-LocalPythonZIP {
    if (Test-Path $LocalPythonExe) { return $LocalPythonExe }

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

# --- 6. TWORZENIE PLIKU STARTOWEGO (DIRECT PYTHON) ---
$PythonLaunchCode = @"
import sys
import os

# Fix dla kodowania w konsoli Windows
sys.stdout.reconfigure(encoding='utf-8')

def start():
    print(f"Uruchamianie loadera dla modelu...")
    try:
        from interpreter.terminal_interface.start_terminal_interface import main
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

Write-Host "--- START: $RawModel (Protocol: OpenAI) ---" -ForegroundColor Green

try {
    # Uruchamiamy python.exe przekazując mu nasz skrypt startowy i parametry
    # Parametr --model ma teraz doklejone "openai/", co naprawia blad OpenRoutera
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
    $env:OPENAI_API_BASE = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
