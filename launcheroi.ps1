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

# Zmienne przekazywane do Pythona
$env:OI_USE_OPENROUTER = "false"

if ($ProvSel -eq "2") {
    $env:OI_USE_OPENROUTER = "true"
    Write-Host "Podaj model (slug z OpenRouter):" -ForegroundColor Yellow
    Write-Host "Np: 'anthropic/claude-3.5-sonnet'" -ForegroundColor DarkGray
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "anthropic/claude-3.5-sonnet" }
    $env:OI_MODEL = $RawModel
} else {
    Write-Host "Podaj model (np. 'gpt-4o'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "gpt-4o" }
    $env:OI_MODEL = $RawModel
}

Write-Host "Wklej klucz API (Będzie widoczny jako *****):" -ForegroundColor Yellow
try {
    $SecureKey = Read-Host "Klucz" -AsSecureString
    $InputKey = [System.Net.NetworkCredential]::new("", $SecureKey).Password
} catch {
    $InputKey = ""
}

if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }

$env:OI_API_KEY = $InputKey
# Czyścimy standardowe zmienne, żeby nie myliły Pythona
Remove-Item Env:\OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue

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

# --- 6. PLIK STARTOWY (PROVIDER OVERRIDE) ---
$PythonLaunchCode = @"
import sys
import os

sys.stdout.reconfigure(encoding='utf-8')

def start():
    print(f"Uruchamianie Open Interpreter...")
    
    try:
        from interpreter import interpreter
        
        # Pobieramy dane z ENV
        use_openrouter = os.environ.get("OI_USE_OPENROUTER", "false") == "true"
        target_model = os.environ.get("OI_MODEL", "gpt-4o")
        api_key = os.environ.get("OI_API_KEY", "")
        
        # Konfiguracja bazowa
        interpreter.llm.api_key = api_key
        interpreter.llm.model = target_model
        
        if use_openrouter:
            print(f"--- TRYB OPENROUTER (Provider Override) ---")
            print(f"Model: {target_model}")
            
            # Adres OpenRouter
            interpreter.llm.api_base = "https://openrouter.ai/api/v1"
            
            # KLUCZOWY FIX:
            # Wymuszamy, aby silnik uzywal 'openai' jako dostawcy, 
            # niezaleznie od nazwy modelu (nawet jak ma 'anthropic' w nazwie).
            # To eliminuje blad 'Missing Anthropic API Key' oraz blad 400.
            interpreter.llm.custom_llm_provider = "openai"
            
            # Parametry bezpieczenstwa
            interpreter.llm.context_window = 128000
            interpreter.llm.max_tokens = 4096 
        else:
            print(f"--- TRYB OPENAI ---")
            # Dla zwyklego OpenAI nic nie wymuszamy, auto-detekcja dziala
        
        interpreter.auto_run = True
        interpreter.system_message = "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
        
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
    & "$PyCmd" "$PyStartFile"
} catch {
    Write-Error "Błąd uruchomienia: $_"
} finally {
    $env:OI_API_KEY = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
