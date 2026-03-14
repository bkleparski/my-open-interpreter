# my-open-interpreter

Zestaw skryptów PowerShell automatyzujących instalację i uruchamianie [Open Interpreter](https://github.com/OpenInterpreter/open-interpreter) na Windows. Każdy launcher obsługuje inny scenariusz użycia.

## Skrypty

### `launcher.ps1` — Tryb Deepseek (stały)
Uruchamia Open Interpreter z modelem **Deepseek** przez prywatny endpoint Ollama (`ollama.ebartnet.pl`).

- Automatycznie instaluje **Python 3.11** (przez winget), jeśli nie jest dostępny
- Tworzy trwałe środowisko wirtualne w `~\.oi_deepseek_launcher\venv`
- Klucz API wczytywany z:
  - zmiennej środowiskowej `OPENAI_API_KEY`, lub
  - pliku `~\.oi_deepseek_launcher\.env`
- Odpowiedzi w języku polskim

### `launcheroi.ps1` — Tryb sesji z auto-destrukcją
Uruchamia Open Interpreter w trybie tymczasowym — wszystkie pliki są **usuwane po zakończeniu sesji**.

- Menu wyboru dostawcy: **OpenAI** lub **OpenRouter**
- Klucz API wprowadzany bezpiecznie przez `SecureString` (niewidoczny w terminalu)
- Pobiera i instaluje Pythona lokalnie (w `~\.oi_gpt_codex`) — nie ingeruje w system
- Po zakończeniu sesji automatycznie usuwa klucz z pamięci i czyści pliki z dysku

### `launcheroiollama.ps1` — Tryb RAM z OpenAI
Uproszczony launcher sesji tymczasowej z modelem **gpt-4o**.

- Używa Pythona systemowego (lub instaluje przez winget)
- Klucz API tylko w pamięci RAM — nie jest zapisywany na dysku
- Auto-destrukcja katalogu roboczego `~\.oi_session_temp` po zakończeniu

## Wymagania

- Windows 10 / Windows 11
- PowerShell 5.1+
- `winget` (App Installer) — dostępny domyślnie w Windows 11
- Połączenie z Internetem
- Klucz API (OpenAI / OpenRouter) — w zależności od wybranego launchera

## Użycie

```powershell
# Launcher z Deepseek (wymaga pliku .env lub zmiennej środowiskowej)
.\launcher.ps1

# Launcher z wyborem dostawcy (sesja tymczasowa)
.\launcheroi.ps1

# Launcher z gpt-4o (sesja RAM)
.\launcheroiollama.ps1
```

> **Uwaga:** Skrypty mogą wymagać zezwolenia na wykonanie. Jeśli PowerShell blokuje uruchomienie, wykonaj:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```
