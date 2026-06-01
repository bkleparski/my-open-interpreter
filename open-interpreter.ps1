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
        Packages = @("open-interpreter", "litellm")
    }
    "2" = @{
        Label    = "OpenAI GPT-5.5"
        Model    = "gpt-5.5"
        ApiBase  = ""
        ApiUrl   = "https://platform.openai.com/api-keys"
        Provider = "openai"
        Ctx      = 128000
        MaxTok   = 16384
        Packages = @("open-interpreter")
    }
    "3" = @{
        Label    = "Gemini 2.5 Flash"
        Model    = "gemini/gemini-2.5-flash"
        ApiBase  = ""
        ApiUrl   = "https://aistudio.google.com/apikey"
        Provider = "gemini"
        Ctx      = 1000000
        MaxTok   = 65536
        Packages = @("open-interpreter", "litellm", "google-generativeai")
    }
}

# ============================================================
# STATYCZNY SKRYPT PYTHON (bez interpolacji PS w kodzie Py)
# Wszystkie roznicy miedzy providerami obsluguje sam Python
# przez zmienne srodowiskowe OI_PROVIDER i OI_API_BASE.
# ============================================================
$PyLines = @(
    "import os, sys",
    "sys.stdout.reconfigure(encoding='utf-8', errors='replace')",
    "",
    "def main():",
    "    try:",
    "        from interpreter import interpreter",
    "    except ImportError:",
    "        print('BLAD: open-interpreter nie jest zainstalowany w tym srodowisku.')",
    "        sys.exit(1)",
    "",
    "    provider = os.environ.get('OI_PROVIDER', '')",
    "    api_base = os.environ.get('OI_API_BASE', '')",
    "",
    "    if provider == 'gemini':",
    "        os.environ['GOOGLE_API_KEY'] = os.environ['OI_API_KEY']",
    "",
    "    interpreter.llm.model  = os.environ['OI_MODEL']",
    "    interpreter.llm.api_key = os.environ['OI_API_KEY']",
    "",
    "    if api_base:",
    "        interpreter.llm.api_base = api_base",
    "",
    "    interpreter.llm.context_window = int(os.environ.get('OI_CTX', '65536'))",
    "    interpreter.llm.max_tokens     = int(os.environ.get('OI_MAX', '4096'))",
    "    interpreter.auto_run           = True",
    "    interpreter.system_message     = (",
    "        'Jestes asystentem IT. Wykonujesz polecenia na Windows. '",
    "        'Odpowiadaj zwiezle i po polsku. '",
    "        'Przed wykonaniem destruktywnych komend zapytaj o potwierdzenie.'",
    "    )",
    "",
    "    print()",
    "    print('  Model    : ' + interpreter.llm.model)",
    "    print('  Provider : ' + provider)",
    "    print('  Wpisz exit aby zakonczyc.')",
    "    print()",
    "    interpreter.chat()",
    "",
    "if __name__ == '__main__':",
    "    main()"
)

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

    # Naglowek
    Clear-Host
    Write-Host ""
    Write-Host "  Open Interpreter · $($cfg.Label)" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # Python
    $PyCmd = Get-Python
    if (-not $PyCmd) {
        Write-Host "  BLAD: Nie mozna znalezc ani zainstalowac Python 3.11." -ForegroundColor Red
        $null = Read-Host "  Nacisnij Enter aby wrocic"
        continue
    }

    # Instalacja srodowiska (jednorazowo, venv zostaje)
    if (-not (Test-Path "$VenvPath\Scripts\python.exe")) {
        Write-Host "  Pierwsza instalacja — tworzenie srodowiska..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
        New-Venv $PyCmd $VenvPath

        if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
            Write-Host "  BLAD: Nie udalo sie utworzyc venv." -ForegroundColor Red
            $null = Read-Host "  Nacisnij Enter aby wrocic"
            continue
        }

        Write-Host "  Instalacja pakietow..." -ForegroundColor Yellow
        & "$VenvPath\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel --quiet
        foreach ($pkg in $cfg.Packages) {
            Write-Host "    pip install $pkg" -ForegroundColor DarkGray
            & "$VenvPath\Scripts\pip.exe" install $pkg --quiet
        }
        Write-Host "  Instalacja zakonczona." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "  Srodowisko gotowe (cache)." -ForegroundColor DarkGray
        Write-Host ""
    }

    # Klucz API
    Write-Host "  Klucz API — $($cfg.Label)" -ForegroundColor White
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

    # Zapisz statyczny skrypt Python
    $PyCode = $PyLines -join "`n"
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
    Set-Content -Path $PyScript -Value $PyCode -Encoding UTF8

    # Uruchomienie
    try {
        $env:OI_MODEL    = $cfg.Model
        $env:OI_API_KEY  = $ApiKey
        $env:OI_API_BASE = $cfg.ApiBase
        $env:OI_PROVIDER = $cfg.Provider
        $env:OI_CTX      = $cfg.Ctx.ToString()
        $env:OI_MAX      = $cfg.MaxTok.ToString()

        & "$VenvPath\Scripts\python.exe" $PyScript
    }
    finally {
        $env:OI_API_KEY     = $null
        $env:OI_API_BASE    = $null
        $env:OI_PROVIDER    = $null
        $env:GOOGLE_API_KEY = $null
        $ApiKey             = $null
        Remove-Item $PyScript -ErrorAction SilentlyContinue
        Write-Host "`n  Klucz API usunieto z pamieci sesji." -ForegroundColor DarkGray
        $null = Read-Host "  Nacisnij Enter aby wrocic do menu"
    }
}
