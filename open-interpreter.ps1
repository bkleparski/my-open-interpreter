<#
.SYNOPSIS
    Open Interpreter — launcher
    irm go.ebartnet.pl/open-interpreter | iex
.DESCRIPTION
    Menu wyboru wersji: DeepSeek V4 Flash / OpenAI GPT-5.5 / Gemini 2.5 Flash
    Klucz API podawany interaktywnie — nigdy nie jest zapisywany na dysku.
#>

$BASE = "https://raw.githubusercontent.com/bkleparski/my-open-interpreter/main"

function Show-Menu {
    Clear-Host
    Write-Host "" 
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        Open Interpreter — Launcher           ║" -ForegroundColor Cyan
    Write-Host "  ║   github.com/bkleparski/my-open-interpreter  ║" -ForegroundColor DarkGray
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Wybierz model AI:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  DeepSeek V4 Flash     (api.deepseek.com)" -ForegroundColor Yellow
    Write-Host "  [2]  OpenAI GPT-5.5        (api.openai.com)" -ForegroundColor Green
    Write-Host "  [3]  Gemini 2.5 Flash      (generativelanguage.googleapis.com)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [0]  Wyjdz" -ForegroundColor DarkGray
    Write-Host ""
}

do {
    Show-Menu
    $choice = Read-Host "  Wybor"
    switch ($choice) {
        "1" {
            Write-Host "`n  Ladowanie: DeepSeek V4 Flash..." -ForegroundColor Cyan
            Invoke-Expression (Invoke-RestMethod -Uri "$BASE/oi-deepseek.ps1")
        }
        "2" {
            Write-Host "`n  Ladowanie: OpenAI GPT-5.5..." -ForegroundColor Cyan
            Invoke-Expression (Invoke-RestMethod -Uri "$BASE/oi-openai.ps1")
        }
        "3" {
            Write-Host "`n  Ladowanie: Gemini 2.5 Flash..." -ForegroundColor Cyan
            Invoke-Expression (Invoke-RestMethod -Uri "$BASE/oi-gemini.ps1")
        }
        "0" {
            Write-Host "`n  Do zobaczenia!" -ForegroundColor Green
        }
        default {
            Write-Host "`n  Nieznana opcja." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "0")
