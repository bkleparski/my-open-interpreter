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
Write-Host "--- OPEN INTERPRETER (2026 SSL FIX) ---" -ForegroundColor Cyan
Write-Host "Tryb incognito: Klucze tylko w RAM." -ForegroundColor Gray
Write-Host "------------------------------------------------" -ForegroundColor DarkGray

Write-Host "Wybierz dostawcę:" -ForegroundColor Cyan
Write-Host "[1] OpenAI" -ForegroundColor White
Write-Host "[2] OpenRouter" -ForegroundColor White

$ProvSel = Read-Host "Wybór"

# Zmienne logiczne
$UseOpenRouter = $false
$TargetModel = ""

if ($ProvSel -eq "2") {
    $UseOpenRouter = $true
    Write-Host "Podaj model (slug z OpenRouter):" -ForegroundColor Yellow
    Write-Host "Np: 'anthropic/claude-3.5-sonnet'" -ForegroundColor DarkGray
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "anthropic/claude-3.5-sonnet" }
    
    # NATIVE LITELLM: Dodajemy 'openrouter/' żeby silnik wiedział co robić
    if ($RawModel -match "^openrouter/") {
        $TargetModel = $RawModel
    } else {
        $TargetModel = "openrouter/$RawModel"
    }
} else {
    Write-Host "Podaj model (np. 'gpt-4o'):" -ForegroundColor Yellow
    $RawModel = Read-Host "Model"
    if ([string]::IsNullOrWhiteSpace($RawModel)) { $RawModel = "gpt-4o" }
    $TargetModel = $RawModel
}

Write-Host "Wklej klucz API (Będzie widoczny jako *****):" -ForegroundColor Yellow
try {
    $SecureKey = Read-Host "Klucz" -AsSecureString
    $InputKey = [System.Net.NetworkCredential]::new("", $SecureKey).Password
} catch {
    $InputKey = ""
}

if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }

# --- CZYSTE ZMIENNE ŚRODOWISKOWE ---
# Usuwamy wszystko co może bruździć
Remove-Item Env:\OPENAI_API_BASE -ErrorAction SilentlyContinue
Remove-Item Env:\OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

if ($UseOpenRouter) {
    # Dla OpenRouter ustawiamy DEDYKOWANĄ zmienną.
    # Nie ustawiamy OPENAI_API_KEY, żeby nie mylić silnika.
    $env:OPENROUTER_API_KEY = $InputKey
} else {
    # Dla OpenAI standard
    $env:OPENAI_API_KEY = $InputKey
}

# --- 3. ZAPIS STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "`n--- Inicjowanie środowiska (Metoda Portable ZIP) ---" -ForegroundColor Cyan

# --- 4. INSTALACJA PYTHON I SSL FIX ---
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

# --- 5. INSTALACJA PAKIETÓW + CERTIFI (SSL FIX) ---
Write-Host "Instalacja bibliotek i certyfikatów SSL..." -ForegroundColor Yellow
# Instalujemy certifi aby naprawić błąd 520/SSL
& "$PyCmd" -m pip install --upgrade pip setuptools wheel certifi --no-warn-script-location --quiet
& "$PyCmd" -m pip install open-interpreter --no-warn-script-location --quiet

# --- 6. PLIK STARTOWY (CERTS + NATIVE RUN) ---
$PythonLaunchCode = @"
import sys
import os
import certifi

# SSL FIX: Wskazujemy Pythonowi gdzie są certyfikaty
os.environ['SSL_CERT_FILE'] = certifi.where()

sys.stdout.reconfigure(encoding='utf-8')

def start():
    print(f"Uruchamianie Open Interpreter...")
    print(f"Certyfikaty SSL: {certifi.where()}")
    
    try:
        from interpreter import interpreter
        
        # Odbieramy argumenty z CLI (przekazane przez PowerShella)
        # Nie ustawiamy tu nic recznie, polegamy na Zmiennych Srodowiskowych
        # i natywnej obsludze 'openrouter/' przez LiteLLM.
        
        interpreter.auto_run = True
        interpreter.system_message = "Jesteś ekspertem IT. Wykonujesz polecenia w systemie Windows. Odpowiadaj zwięźle i po polsku."
        
        # Konfiguracja bezpieczenstwa
        interpreter.llm.context_window = 128000
        interpreter.llm.max_tokens = 4096
        
        # Start
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

Write-Host "--- START: $TargetModel ---" -ForegroundColor Green

try {
    # Przekazujemy model jako argument CLI do interpretera wewnątrz Pythona
    # To najbezpieczniejsza metoda.
    
    # Budujemy komendę:
    # python.exe start_oi.py --model nazwa_modelu
    
    $StartArgs = @(
        "$PyStartFile",
        "--model", "$TargetModel",
        "-y"
    )
    
    & "$PyCmd" $StartArgs
    
} catch {
    Write-Error "Błąd uruchomienia: $_"
} finally {
    $env:OPENAI_API_KEY = $null
    $env:OPENROUTER_API_KEY = $null
    $InputKey = $null
    Write-Host "`n[SECURE] Wyczyszczono klucze z pamięci." -ForegroundColor DarkGray
}
