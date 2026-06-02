#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Open Interpreter - Launcher
    irm go.ebartnet.pl/open-interpreter | iex
#>

# ============================================================
# KONFIGURACJE MODELI
# ============================================================
$configs = @{
    "1" = @{
        Label    = "DeepSeek V4 Flash"
        # openai/ prefix = litellm uzywa OpenAI client (bez DeepSeek-specific params)
        # OPENAI_API_BASE ustawiony w env zmusza klienta na wlasciwy endpoint
        Model    = "openai/deepseek-chat"
        ApiBase  = "https://api.deepseek.com"
        ApiUrl   = "https://platform.deepseek.com"
        Provider = "deepseek"
        Ctx      = 65536
        MaxTok   = 4096
        Packages = @("open-interpreter")
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
        Packages = @("open-interpreter", "google-generativeai")
    }
}

# ============================================================
# STATYCZNY SKRYPT PYTHON
# ============================================================
$PyLines = @(
    "import os, sys",
    "sys.stdout.reconfigure(encoding='utf-8', errors='replace')",
    "",
    "def main():",
    "    try:",
    "        from interpreter import interpreter",
    "    except Exception as e:",
    "        print('BLAD importu: ' + type(e).__name__ + ': ' + str(e))",
    "        sys.exit(1)",
    "",
    "    provider = os.environ.get('OI_PROVIDER', '')",
    "    api_base = os.environ.get('OI_API_BASE', '')",
    "",
    "    # Gemini wymaga GOOGLE_API_KEY",
    "    if provider == 'gemini':",
    "        os.environ['GOOGLE_API_KEY'] = os.environ['OI_API_KEY']",
    "",
    "    # DeepSeek: ustaw OPENAI_API_BASE zeby litellm uzyl wlasciwego endpointu",
    "    if provider == 'deepseek' and api_base:",
    "        os.environ['OPENAI_API_BASE'] = api_base",
    "",
    "    interpreter.llm.model              = os.environ['OI_MODEL']",
    "    interpreter.llm.api_key            = os.environ['OI_API_KEY']",
    "    interpreter.llm.supports_functions = False",
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
    "    if api_base:",
    "        print('  Endpoint : ' + api_base)",
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
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "       Open Interpreter -- Launcher           " -ForegroundColor Cyan
    Write-Host "   github.com/bkleparski/my-open-interpreter  " -ForegroundColor DarkGray
    Write-Host "  ============================================" -ForegroundColor Cyan
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

function Test-OiInstalled {
    param($VenvPython)
    $out = & $VenvPython -c "from interpreter import interpreter; print('OI_OK')" 2>&1
    return ($out -match "OI_OK")
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
    $VenvPy   = "$VenvPath\Scripts\python.exe"
    $PyScript = "$BasePath\run.py"

    Clear-Host
    Write-Host ""
    Write-Host "  Open Interpreter -- $($cfg.Label)" -ForegroundColor Cyan
    Write-Host "  ------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $PyCmd = Get-Python
    if (-not $PyCmd) {
        Write-Host "  BLAD: Nie mozna znalezc ani zainstalowac Python 3.11." -ForegroundColor Red
        $null = Read-Host "  Nacisnij Enter aby wrocic"
        continue
    }

    $venvOk = Test-Path $VenvPy
    $oiOk   = $venvOk -and (Test-OiInstalled $VenvPy)

    if (-not $venvOk -or -not $oiOk) {
        if ($venvOk -and -not $oiOk) {
            Write-Host "  Brak open-interpreter -- reinstalacja..." -ForegroundColor Yellow
            Remove-Item $VenvPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "  Tworzenie srodowiska..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
        New-Venv $PyCmd $VenvPath

        if (-not (Test-Path "$VenvPath\Scripts\pip.exe")) {
            Write-Host "  BLAD: Nie udalo sie utworzyc venv." -ForegroundColor Red
            $null = Read-Host "  Nacisnij Enter aby wrocic"
            continue
        }

        $total = 1 + $cfg.Packages.Count + 1
        Write-Host ""
        Write-Host "  [1/$total] Aktualizacja pip + wheel" -ForegroundColor DarkGray
        & $VenvPy -m pip install --upgrade pip wheel

        $step = 2
        foreach ($pkg in $cfg.Packages) {
            Write-Host ""
            Write-Host "  [$step/$total] pip install $pkg" -ForegroundColor Yellow
            & "$VenvPath\Scripts\pip.exe" install $pkg
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  BLAD: pip install $pkg (kod $LASTEXITCODE)" -ForegroundColor Red
                $null = Read-Host "  Nacisnij Enter aby wrocic"
                continue
            }
            $step++
        }

        Write-Host ""
        Write-Host "  [$total/$total] Upgrade litellm (nowe modele)" -ForegroundColor Yellow
        & "$VenvPath\Scripts\pip.exe" install "litellm<2.0" --upgrade

        Write-Host ""
        Write-Host "  Weryfikacja importu..." -ForegroundColor DarkGray
        $verify = & $VenvPy -c "from interpreter import interpreter; print('OI_OK')" 2>&1
        if (-not ($verify -match "OI_OK")) {
            Write-Host "  BLAD: $verify" -ForegroundColor Red
            $null = Read-Host "  Nacisnij Enter aby wrocic"
            continue
        }
        Write-Host "  OK -- srodowisko gotowe." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "  Srodowisko gotowe (cache)." -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  Klucz API -- $($cfg.Label)" -ForegroundColor White
    Write-Host "  Gdzie zdobyc: $($cfg.ApiUrl)" -ForegroundColor DarkGray
    Write-Host "  Klucz nie bedzie zapisany -- tylko w pamieci RAM tej sesji." -ForegroundColor DarkGray
    Write-Host ""
    $SecureKey = Read-Host "  Klucz API" -AsSecureString
    $ApiKey    = [System.Net.NetworkCredential]::new("", $SecureKey).Password
    $SecureKey.Dispose()

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "`n  Nie podano klucza. Powrot do menu." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $PyCode = $PyLines -join "`n"
    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
    Set-Content -Path $PyScript -Value $PyCode -Encoding UTF8

    try {
        $env:OI_MODEL    = $cfg.Model
        $env:OI_API_KEY  = $ApiKey
        $env:OI_API_BASE = $cfg.ApiBase
        $env:OI_PROVIDER = $cfg.Provider
        $env:OI_CTX      = $cfg.Ctx.ToString()
        $env:OI_MAX      = $cfg.MaxTok.ToString()

        # Dla DeepSeek: ustaw OPENAI_API_KEY zeby openai client go uzywal
        if ($cfg.Provider -eq "deepseek") {
            $env:OPENAI_API_KEY  = $ApiKey
            $env:OPENAI_API_BASE = $cfg.ApiBase
        }

        & $VenvPy $PyScript
    }
    finally {
        $env:OI_API_KEY      = $null
        $env:OI_API_BASE     = $null
        $env:OI_PROVIDER     = $null
        $env:OPENAI_API_KEY  = $null
        $env:OPENAI_API_BASE = $null
        $env:GOOGLE_API_KEY  = $null
        $ApiKey              = $null
        Remove-Item $PyScript -ErrorAction SilentlyContinue
        Write-Host "`n  Klucz API usunieto z pamieci sesji." -ForegroundColor DarkGray
        $null = Read-Host "  Nacisnij Enter aby wrocic do menu"
    }
}
