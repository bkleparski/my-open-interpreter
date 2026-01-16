# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$LocalPythonDir = "$BasePath\python_bin"
$LocalPythonExe = "$LocalPythonDir\python.exe"
$VenvPath = "$BasePath\venv"
$LauncherFile = "$BasePath\oi.ps1"
$ModelName = "gpt-5.2-codex"

# --- 0. DIAGNOSTYKA I CZYSZCZENIE ---
# Sprawdzamy, czy w venv jest właściwa architektura. Jeśli nie - usuwamy.
if (Test-Path "$VenvPath\Scripts\python.exe") {
    try {
        # Test: Czy Python w venv uważa się za AMD64?
        $arch = & "$VenvPath\Scripts\python" -c "import platform; print(platform.machine())" 2>$null
        if ($arch -notmatch "AMD64|x86_64") { throw "Wrong Architecture" }
    } catch {
        Write-Host "Wykryto złą architekturę w starym venv. Usuwanie..." -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 1. INICJALIZACJA KATALOGU ---
if (-not (Test-Path $BasePath)) { New-Item -ItemType Directory -Force -Path $BasePath | Out-Null }

# --- 2. LOGIKA KLUCZA ---
$ApiKey = $null
if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) { $ApiKey = $env:OPENAI_API_KEY }
elseif (Test-Path "$BasePath\.env") {
    foreach ($line in Get-Content "$BasePath\.env") {
        if ($line -match "^OPENAI_API_KEY=(.*)$") { $ApiKey = $matches[1].Trim() }
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "`n--- KONFIGURACJA ---" -ForegroundColor Yellow
    $InputKey = Read-Host "Wklej klucz OpenAI API (sk-...)"
    if ([string]::IsNullOrWhiteSpace($InputKey)) { Write-Error "Brak klucza."; exit }
    $ApiKey = $InputKey.Trim()
    Set-Content -Path "$BasePath\.env" -Value "OPENAI_API_KEY=$ApiKey"
}

# --- 3. ZAPISANIE STARTERA ---
$CurrentScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if (-not (Test-Path $LauncherFile) -and $CurrentScriptBlock) {
    try { Set-Content -Path $LauncherFile -Value $CurrentScriptBlock.ToString() } catch {}
}

Write-Host "--- Inicjowanie Loadera Open Interpreter (Izolacja x64) ---" -ForegroundColor Cyan

# --- FUNKCJA: INSTALACJA PRYWATNEGO PYTHONA X64 ---
function Ensure-LocalPythonX64 {
    # Sprawdź czy nasz lokalny python istnieje i czy jest x64
    if (Test-Path $LocalPythonExe) {
        try {
            $arch = & $LocalPythonExe -c "import platform; print(platform.machine())" 2>$null
            if ($arch -match "AMD64|x86_64") { 
                return $LocalPythonExe 
            }
        } catch {}
        Write-Host "Lokalny Python uszkodzony. Pobieranie ponownie..." -ForegroundColor Yellow
        Remove-Item $LocalPythonDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Pobieranie dedykowanego Pythona 3.11 (x64) dla emulacji..." -ForegroundColor Yellow
    
    $InstallerUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $InstallerPath = "$BasePath\python_installer.exe"
    
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath
        
        Write-Host "Instalowanie Pythona w folderze lokalnym..." -ForegroundColor Yellow
        # Instalacja cicha, do folderu skryptu, bez admina, bez modyfikacji PATH
        $args = "/quiet InstallAllUsers=0 TargetDir=`"$LocalPythonDir`" PrependPath=0 Include_test=0 Include_doc=0 Include_tcltk=0 Shortcuts=0"
        
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $args -Wait -PassThru
        
        if ($process.ExitCode -ne 0) { throw "Błąd instalatora: $($process.ExitCode)" }
        
        Remove-Item $InstallerPath -ErrorAction SilentlyContinue
        
        if (Test-Path $LocalPythonExe) {
            Write-Host "Zainstalowano pomyślnie." -ForegroundColor Green
            return $LocalPythonExe
        } else {
            throw "Plik python.exe nie pojawił się po instalacji."
        }
    } catch {
        Write-Error "Nie udało się pobrać/zainstalować lokalnego Pythona: $_"
        exit
    }
}

# Pobierz/Znajdź izolowanego Pythona
$PyCmd = Ensure-LocalPythonX64
Write-Host "Używanie izolowanego interpretera: $PyCmd" -ForegroundColor Green

# --- KONFIGURACJA VENV ---
if (-not (Test-Path "$VenvPath\Scripts\interpreter.exe")) {
    Write-Host "Tworzenie venv (wymuszona architektura x64)..." -ForegroundColor Yellow
    
    & $PyCmd -m venv $VenvPath
    
    if (-not (Test-Path "$VenvPath\Scripts\python.exe")) {
        Write-Error "Nie udało się utworzyć venv."
        exit
    }

    Write-Host "Instalacja pakietów (teraz pobierze wersje binarne)..." -ForegroundColor Yellow
    # Aktualizacja pip wewnątrz venv
    & "$VenvPath\Scripts\python" -m pip install --upgrade pip setuptools wheel --quiet
    # Instalacja Open Interpreter
    & "$VenvPath\Scripts\pip" install open-interpreter --quiet
}

# --- URUCHOMIENIE ---
$env:OPENAI_API_KEY = $ApiKey
if ($env:OPENAI_API_BASE) { Remove-Item Env:\OPENAI_API_BASE } 

Write-Host "--- START: $ModelName ---" -ForegroundColor Green

try {
    & "$VenvPath\Scripts\interpreter" `
        --model $ModelName `
        --context_window 128000 `
        --max_tokens 8192 `
        -y `
        --system_message "Jesteś ekspertem IT. Wykonujesz polecenia w Windows. Odpowiadaj zwięźle po polsku."
} catch {
    Write-Error "Błąd uruchomienia."
}
