# Open Interpreter — Launcher

Trzy wersje Open Interpreter uruchamiane jednym poleceniem.
Klucz API podawany interaktywnie — **nigdy nie jest zapisywany na dysku**.

## Uruchomienie

```powershell
irm go.ebartnet.pl/open-interpreter | iex
```

> Terminal PowerShell — **nie wymaga uprawnien Admin**.

---

## Dostepne modele

| Opcja | Model | Provider |
|---|---|---|
| `[1]` | DeepSeek V4 Flash | api.deepseek.com |
| `[2]` | OpenAI GPT-5.5 | api.openai.com |
| `[3]` | Gemini 2.5 Flash | Google AI Studio |

---

## Gdzie zdobyc klucz API

| Provider | URL |
|---|---|
| DeepSeek | https://platform.deepseek.com |
| OpenAI | https://platform.openai.com/api-keys |
| Google | https://aistudio.google.com/apikey |

---

## Jak dziala

1. **Pierwsze uruchomienie** — instaluje Python 3.11 (jezeli brak) i pakiety (~5-10 min)
2. **Kolejne uruchomienia** — start w kilka sekund (venv w cache)
3. **Klucz API** — podajesz interaktywnie, trzymany tylko w pamieci RAM sesji
4. **Po wyjsciu** — klucz zerowany z pamieci, plik tymczasowy usuwany

### Cache srodowisk

```
%USERPROFILE%\.oi\deepseek\venv\   ← DeepSeek
%USERPROFILE%\.oi\openai\venv\    ← OpenAI
%USERPROFILE%\.oi\gemini\venv\    ← Gemini
```

Aby wymusic reinstalacje — usun odpowiedni folder.

---

## Autor

**Bartek Kleparski** — [ebartnet.pl](https://ebartnet.pl)  
Ravnet Sp. z o.o.
