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

# Zmienne przekazywane do Pythona przez ENV
$env:OI_USE_OPENROUTER = "false"
$env:OI_REAL_MODEL = ""

if ($ProvSel -eq "2") {
    # OPENROUTER
    $env:OI_USE_OPENROUTER = "true"
    Write-Host "Podaj model (slug z OpenRouter):" -ForegroundColor Yellow
    Write-Host "Np: 'anthropic/claude-3.5-sonnet' (Zalecany)" -ForegroundColor DarkGray
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "anthropic/claude-3.5-sonnet" }
    $env:OI_REAL_MODEL = $RawModel
} else {
    # OPENAI
    Write-Host "Podaj model (np. 'gpt-4o'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "gpt-4o" }
    $env:OI_REAL_MODEL = $RawModel
}

Write-Host "Wklej klucz API (Będzie widoczny jako *****):" -ForegroundColor Yellow
try {
    $SecureKey = Read-Host "Klucz" -AsSecureString
    $InputKey = [System.Net.NetworkCredential]::new("", $SecureKey).Password
} catch {
    $InputKey = ""
}

if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }

# Ustawiamy klucz w zmiennej środowiskowej
$env:OPENAI_API_KEY = $InputKey
# Czyścimy stare API Base, bo ustawimy je w Pythonie
if (Test-Path Env:\OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue }

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

# --- 6. PLIK STARTOWY (PYTHON CONFIGURATION & SPOOFING) ---
$PythonLaunchCode = @"
import sys
import os
import time

# Wymuszenie UTF-8 w konsoli Windows
sys.stdout.reconfigure(encoding='utf-8')

def start():
    print(f"Uruchamianie Open Interpreter...")
    
    try:
        # Importujemy interpreter
        from interpreter import interpreter
        
        # Pobieramy konfiguracje ze zmiennych srodowiskowych
        use_openrouter = os.environ.get("OI_USE_OPENROUTER", "false") == "true"
        real_model = os.environ.get("OI_REAL_MODEL", "gpt-4o")
        
        if use_openrouter:
            print(f"--- TRYB OPENROUTER (SPOOFING) ---")
            print(f"Cel: {real_model}")
            
            # 1. Ustawiamy API Base na OpenRouter
            interpreter.llm.api_base = "https://openrouter.ai/api/v1"
            
            # 2. MANEWR PODMIANY:
            # Mowimy interpreterowi, ze to 'gpt-4o'. Dzieki temu uzyje protokolu OpenAI 
            # i nie bedzie szukal kluczy Anthropic/Google.
            interpreter.llm.model = "gpt-4o"
            
            # 3. Wstrzykujemy prawdziwa nazwe modelu w cialo zapytania HTTP.
            # To nadpisuje 'gpt-4o' w ostatniej chwili.
            interpreter.llm.extra_body = { "model": real_model }
            
            # Ustawienia kontekstu dla nowoczesnych modeli
            interpreter.llm.context_window = 128000
            interpreter.llm.max_tokens = 8192
            
        else:
            print(f"--- TRYB OPENAI ---")
            interpreter.llm.model = real_model
        
        # Wspolne ustawienia
        interpreter.auto_run = True
        interpreter.system_message = "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
        
        # Start czatu
        interpreter.chat()
        
    except Exception as e:
        print(f"\nCRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        input('\nWcisnij ENTER aby zamknac...')

if __name__ == "__main__":
    start()
"@

Set-Content -Path $PyStartFile -Value $PythonLaunchCode

Write-Host "--- START ---" -ForegroundColor Green

try {
    # Uruchamiamy skrypt Pythona
    & "$PyCmd" "$PyStartFile"
} catch {
    Write-Error "Błąd uruchomienia: $_"
} finally {
    # Czyszczenie
    $env:OPENAI_API_KEY = $null
    $env:OI_USE_OPENROUTER = $null
    $env:OI_REAL_MODEL = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
