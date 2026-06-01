<#
.SYNOPSIS
    Open Interpreter — Google Gemini 2.5 Flash
    Model: gemini/gemini-2.5-flash | Endpoint: generativelanguage.googleapis.com
    Klucz API podawany interaktywnie, NIE jest zapisywany na dysku.
#>

$Provider    = "gemini"
$ModelName   = "gemini/gemini-2.5-flash"
$CtxWindow   = 1000000
$MaxTokens   = 65536
$BasePath    = "$env:USERPROFILE\.oi\$Provider"
$VenvPath    = "$BasePath\venv"
$PyScript    = "$BasePath\run.py"

Write-Host ""
Write-Host "  ┌─────────────────────────────────────────┐" -ForegroundColor Magenta
Write-Host "  │  Open Interpreter · Gemini 2.5 Flash    │" -ForegroundColor Magenta
Write-Host "  └─────────────────────────────────────────┘" -ForegroundColor Magenta
Write-Host ""

# ── 1. PYTHON ─────────────────────────────────────────────────────────────────
function Get-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $v = py -3.11 --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "py -3.11" }
    }
    $std = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    if (Test-Path $std) { return $std }

    Write-Host "  Python 3.11 nie znaleziony. Instalacja przez winget..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install -e --id Python.Python.3.11 --architecture x64 --scope user `
            --accept-source-agreements --accept-package-agreements --silent
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","Machine")
        if (Test-Path $std) { return $std }
    }
    return $null
}

$PyCmd = Get-Python
if (-not $PyCmd) {
    Write-Host "  BLAD: Nie mozna znalezc ani zainstalowac Python 3.11." -ForegroundColor Red
    return
}

# ── 2. INSTALACJA SRODOWISKA (jednorazowo, venv zostaje) ──────────────────────
if (-not (Test-Path "$VenvPath\Scripts\python.exe")) {
    Write-Host "  Pierwsza instalacja — tworzenie srodowiska..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null

    if ($PyCmd -eq "py -3.11") { py -3.11 -m venv $VenvPath }
    else                       { & $PyCmd -m venv $VenvPath }

    if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
        Write-Host "  BLAD: Nie udalo sie utworzyc venv." -ForegroundColor Red
        return
    }

    Write-Host "  Instalacja open-interpreter + google-generativeai..." -ForegroundColor Yellow
    & "$VenvPath\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel --quiet
    & "$VenvPath\Scripts\pip.exe" install open-interpreter litellm google-generativeai --quiet
    Write-Host "  Instalacja zakonczona." -ForegroundColor Green
} else {
    Write-Host "  Srodowisko gotowe (cache)." -ForegroundColor DarkGray
}

# ── 3. KLUCZ API (nigdy nie trafia na dysk) ───────────────────────────────────
Write-Host ""
Write-Host "  Podaj klucz API Google (https://aistudio.google.com/apikey)" -ForegroundColor White
Write-Host "  Klucz nie bedzie zapisany — tylko w pamieci tej sesji." -ForegroundColor DarkGray
Write-Host ""
$SecureKey = Read-Host "  Klucz API" -AsSecureString
$ApiKey    = [System.Net.NetworkCredential]::new("", $SecureKey).Password
$SecureKey.Dispose()

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "  BLAD: Nie podano klucza." -ForegroundColor Red
    return
}

# ── 4. SKRYPT PYTHON ──────────────────────────────────────────────────────────
$PyCode = @"
import os, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def main():
    try:
        from interpreter import interpreter
    except ImportError:
        print("BLAD: open-interpreter nie jest zainstalowany w tym venv.")
        sys.exit(1)

    # Gemini przez litellm wymaga GOOGLE_API_KEY
    os.environ['GOOGLE_API_KEY'] = os.environ['OI_API_KEY']

    interpreter.llm.model         = os.environ['OI_MODEL']
    interpreter.llm.api_key       = os.environ['OI_API_KEY']
    interpreter.llm.context_window = int(os.environ.get('OI_CTX', '100000'))
    interpreter.llm.max_tokens    = int(os.environ.get('OI_MAX', '65536'))
    interpreter.auto_run          = True
    interpreter.system_message    = (
        "Jestes asystentem IT. Wykonujesz polecenia na Windows. "
        "Odpowiadaj zwiezle i po polsku. "
        "Przed wykonaniem potencjalnie destruktywnych komend — zapytaj o potwierdzenie."
    )

    print()
    print(f"  Model   : {interpreter.llm.model}")
    print("  Wpisz 'exit' aby zakonczyc.")
    print()

    interpreter.chat()

if __name__ == '__main__':
    main()
"@

Set-Content -Path $PyScript -Value $PyCode -Encoding UTF8

# ── 5. URUCHOMIENIE ───────────────────────────────────────────────────────────
try {
    $env:OI_MODEL   = $ModelName
    $env:OI_API_KEY = $ApiKey
    $env:OI_CTX     = $CtxWindow.ToString()
    $env:OI_MAX     = $MaxTokens.ToString()

    & "$VenvPath\Scripts\python.exe" $PyScript
}
finally {
    $env:OI_API_KEY      = $null
    $env:GOOGLE_API_KEY  = $null
    $ApiKey = $null
    Remove-Item $PyScript -ErrorAction SilentlyContinue
    Write-Host "`n  Klucz API usunieto z pamieci sesji." -ForegroundColor DarkGray
}
