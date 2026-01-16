# --- KONFIGURACJA I BEZPIECZEŃSTWO ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

$BasePath = "$env:USERPROFILE\.oi_gpt_codex"
$LocalPythonDir = "$BasePath\python_bin"
$LocalPythonExe = "$LocalPythonDir\python.exe"
$VenvPath = "$BasePath\venv"
$PyStartFile = "$BasePath\start_oi.py"

# --- 1. START (CZYSTY STÓŁ) ---
if (Test-Path $BasePath) { 
    Write-Host "Czyszczenie pozostałości..." -ForegroundColor DarkGray
    Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue 
}
New-Item -ItemType Directory -Force -Path $BasePath | Out-Null

# --- 2. MENU KONFIGURACJI ---
Clear-Host
Write-Host "--- OPEN INTERPRETER (SESSION MODE) ---" -ForegroundColor Cyan
Write-Host "Wszystkie pliki zostaną usunięte po zakończeniu." -ForegroundColor Gray
Write-Host "------------------------------------------------" -ForegroundColor DarkGray

Write-Host "Wybierz dostawcę:" -ForegroundColor Cyan
Write-Host "[1] OpenAI" -ForegroundColor White
Write-Host "[2] OpenRouter" -ForegroundColor White

$ProvSel = Read-Host "Wybór"

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

# --- 3. BLOK GŁÓWNY (TRY...FINALLY) ---
try {
    Write-Host "`n--- INSTALACJA ŚRODOWISKA TYMCZASOWEGO ---" -ForegroundColor Cyan
    
    # A. INSTALACJA PYTHONA (PEŁNY EXE - FIX DLA SSL/CLOUDFLARE)
    Write-Host "Pobieranie Python 3.11 (Full Installer)..." -ForegroundColor Yellow
    $InstUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $InstPath = "$BasePath\python_setup.exe"
    
    Invoke-WebRequest -Uri $InstUrl -OutFile $InstPath
    
    Write-Host "Instalacja silnika Python..." -ForegroundColor Yellow
    $ArgsList = @(
        "/quiet", "InstallAllUsers=0", "TargetDir=$LocalPythonDir", 
        "PrependPath=0", "Include_test=0", "Include_doc=0", 
        "Include_tcltk=0", "Include_pip=1", "Shortcuts=0"
    )
    $proc = Start-Process -FilePath $InstPath -ArgumentList $ArgsList -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Błąd instalacji Pythona: $($proc.ExitCode)" }
    Remove-Item $InstPath -ErrorAction SilentlyContinue

    # B. TWORZENIE VENV
    Write-Host "Tworzenie izolowanego środowiska (venv)..." -ForegroundColor Yellow
    & "$LocalPythonExe" -m venv $VenvPath
    
    # C. INSTALACJA PAKIETÓW
    Write-Host "Instalacja bibliotek i certyfikatów..." -ForegroundColor Yellow
    $Pip = "$VenvPath\Scripts\pip.exe"
    & $Pip install --upgrade pip setuptools wheel certifi --quiet
    & $Pip install open-interpreter --quiet

    # D. GENEROWANIE SKRYPTU STARTOWEGO (Metoda bezpieczna składniowo)
    # Używamy tablicy stringów zamiast Here-String, aby uniknąć błędów parsera
    $PyCodeLines = @(
        "import sys",
        "import os",
        "import certifi",
        "",
        "# SSL FIX",
        "os.environ['SSL_CERT_FILE'] = certifi.where()",
        "os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()",
        "sys.stdout.reconfigure(encoding='utf-8')",
        "",
        "def start():",
        "    try:",
        "        from interpreter import interpreter",
        "        use_openrouter = os.environ.get('OI_USE_OPENROUTER',
