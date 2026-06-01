<#
.SYNOPSIS
    Open Interpreter — Launcher
    irm go.ebartnet.pl/open-interpreter | iex
.DESCRIPTION
    Wybor modelu AI, jednorazowa instalacja srodowiska (cache),
    klucz API tylko w pamieci RAM — nigdy nie trafia na dysk.
#>

# ============================================================
# KONFIGURACJE MODELI
# ============================================================
$configs = @{
    "1" = @{
        Label    = "DeepSeek V4 Flash"
        Model    = "deepseek/deepseek-v4-flash"
        ApiBase  = "https://api.deepseek.com/v1"
        ApiUrl   = "https://platform.deepseek.com"
        Provider = "deepseek"
        Ctx      = 65536
        MaxTok   = 8192
        Packages = "open-interpreter litellm"
    }
    "2" = @{
        Label    = "OpenAI GPT-5.5"
        Model    = "gpt-5.5"
        ApiBase  = ""
        ApiUrl   = "https://platform.openai.com/api-keys"
        Provider = "openai"
        Ctx      = 128000
        MaxTok   = 16384
        Packages = "open-interpreter"
    }
    "3" = @{
        Label    = "Gemini 2.5 Flash"
        Model    = "gemini/gemini-2.5-flash"
        ApiBase  = ""
        ApiUrl   = "https://aistudio.google.com/apikey"
        Provider = "gemini"
        Ctx      = 1000000
        MaxTok   = 65536
        Packages = "open-interpreter litellm google-generativeai"
    }
}

# ============================================================
# MENU
# ============================================================
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔═════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        Open Interpreter — Launcher           ║" -ForegroundColor Cyan
    Write-Host "  ║   github.com/bkleparski/my-open-interpreter  ║" -ForegroundColor DarkGray
    Write-Host "  ╚═════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Wybierz model AI:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  DeepSeek V4 Flash     (api.deepseek.com)" -ForegroundColor Yellow
    Write-Host "  [2]  OpenAI GPT-5.5        (api.openai.com)" -ForegroundColor Green
    Write-Host "  [3]  Gemini 2.5 Flash      (aistudio.google.com)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [0]  Wyjdz" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================
# PYTHON
# ============================================================
function Get-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $null = py -3.11 --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "py311" }
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

function New-Venv {
    param($PyCmd, $VenvPath)
    if ($PyCmd -eq "py311") { py -3.11 -m venv $VenvPath }
    else                    { & $PyCmd -m venv $VenvPath }
}

# ============================================================
# GLOWNA PETLA
# ============================================================
$running = $true
while ($running) {

    Show-Menu
    $choice = Read-Host "  Wybor"

    if ($choice -eq "0") {
        Write-Host "`n  Do zobaczenia!" -ForegroundColor Green
        $running = $false
        break
    }

    if (-not $configs.ContainsKey($choice)) {
        Write-Host "`n  Nieznana opcja." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $cfg      = $configs[$choice]
    $BasePath = "$env:USERPROFILE\.oi\$($cfg.Provider)"
    $VenvPath = "$BasePath\venv"
    $PyScript = "$BasePath\run.py"

    # ---- Naglowek wybranego modelu ----
    Clear-Host
    Write-Host ""
    Write-Host "  Open Interpreter · $($cfg.Label)" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # ---- Python ----
    $PyCmd = Get-Python
    if (-not $PyCmd) {
        Write-Host "  BLAD: Nie mozna znalezc ani zainstalowac Python 3.11." -ForegroundColor Red
        Write-Host "  Nacisnij Enter, aby wrocic do menu..." -ForegroundColor DarkGray
        $null = Read-Host
        continue
    }

    # ---- Instalacja srodowiska (jednorazowo) ----
    if (-not (Test-Path "$VenvPath\Scripts\python.exe")) {
        Write-Host "  Pierwsza instalacja — tworzenie srodowiska..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
        New-Venv $PyCmd $VenvPath

        if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
            Write-Host "  BLAD: Nie udalo sie utworzyc venv." -ForegroundColor Red
            Write-Host "  Nacisnij Enter, aby wrocic do menu..." -ForegroundColor DarkGray
            $null = Read-Host
            continue
        }

        Write-Host "  Instalacja pakietow: $($cfg.Packages)" -ForegroundColor Yellow
        & "$VenvPath\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel --quiet
        foreach ($pkg in $cfg.Packages -split " ") {
            & "$VenvPath\Scripts\pip.exe" install $pkg --quiet
        }
        Write-Host "  Instalacja zakonczona." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "  Srodowisko gotowe (cache)." -ForegroundColor DarkGray
        Write-Host ""
    }

    # ---- Klucz API ----
    Write-Host "  Klucz API $($cfg.Label)" -ForegroundColor White
    Write-Host "  Gdzie zdobyc: $($cfg.ApiUrl)" -ForegroundColor DarkGray
    Write-Host "  Klucz nie bedzie zapisany — tylko w pamieci RAM tej sesji." -ForegroundColor DarkGray
    Write-Host ""
    $SecureKey = Read-Host "  Klucz API" -AsSecureString
    $ApiKey    = [System.Net.NetworkCredential]::new("", $SecureKey).Password
    $SecureKey.Dispose()

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "`n  Nie podano klucza. Powrot do menu." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    # ---- Skrypt Python ----
    $apiBaseLine = if ($cfg.ApiBase) { "    interpreter.llm.api_base = os.environ.get('OI_API_BASE','')" } else { "" }
    $googleLine  = if ($cfg.Provider -eq "gemini") { "    os.environ['GOOGLE_API_KEY'] = os.environ['OI_API_KEY']" } else { "" }

    $PyCode = @"
import os, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def main():
    try:
        from interpreter import interpreter
    except ImportError:
        print('BLAD: open-interpreter nie jest zainstalowany.')
        sys.exit(1)

    $googleLine
    interpreter.llm.model          = os.environ['OI_MODEL']
    interpreter.llm.api_key        = os.environ['OI_API_KEY']
    $apiBaseLine
    interpreter.llm.context_window = int(os.environ.get('OI_CTX','65536'))
    interpreter.llm.max_tokens     = int(os.environ.get('OI_MAX','4096'))
    interpreter.auto_run           = True
    interpreter.system_message     = (
        'Jestes asystentem IT. Wykonujesz polecenia na Windows. '
        'Odpowiadaj zwiezle i po polsku. '
        'Przed wykonaniem destruktywnych komend zapytaj o potwierdzenie.'
    )

    print()
    print(f'  Model : {interpreter.llm.model}')
    print( '  Wpisz exit aby zakonczyc.')
    print()
    interpreter.chat()

if __name__ == '__main__':
    main()
"@

    Set-Content -Path $PyScript -Value $PyCode -Encoding UTF8

    # ---- Uruchomienie ----
    try {
        $env:OI_MODEL    = $cfg.Model
        $env:OI_API_KEY  = $ApiKey
        $env:OI_API_BASE = $cfg.ApiBase
        $env:OI_CTX      = $cfg.Ctx.ToString()
        $env:OI_MAX      = $cfg.MaxTok.ToString()
        if ($cfg.Provider -eq "gemini") { $env:GOOGLE_API_KEY = $ApiKey }

        & "$VenvPath\Scripts\python.exe" $PyScript
    }
    finally {
        # Zerowanie klucza z pamieci
        $env:OI_API_KEY     = $null
        $env:GOOGLE_API_KEY = $null
        $ApiKey             = $null
        Remove-Item $PyScript -ErrorAction SilentlyContinue
        Write-Host "`n  Klucz API usunieto z pamieci sesji." -ForegroundColor DarkGray
        Write-Host "  Nacisnij Enter, aby wrocic do menu..." -ForegroundColor DarkGray
        $null = Read-Host
    }
}
