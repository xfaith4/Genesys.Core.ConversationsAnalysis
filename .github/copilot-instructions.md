# Genesys.Core.ConversationsAnalysis — Copilot Instructions

## Big picture (Core-first architecture)
- This repo is a **PowerShell + WPF desktop shell** over `Genesys.Core`; app code focuses on UX, drilldown, indexing, and exports.
- `App.ps1` is the entry point: load modules, run Gate A initialization, load `XAML/MainWindow.xaml`, then dot-source `App.UI.ps1`.
- `App.CoreAdapter.psm1` is the **single integration boundary** to `Genesys.Core`.
	- Only this module may call/import: `Import-Module` (Core), `Assert-Catalog`, `Invoke-Dataset`.
	- Use `Start-PreviewRun` (`analytics-conversation-details-query`) and `Start-FullRun` (`analytics-conversation-details`).

## Hard boundaries to preserve
- Do **not** call `/api/v2/` anywhere in app code.
- Do **not** use `Invoke-RestMethod`/`Invoke-WebRequest` outside `App.Auth.psm1`.
- Do **not** import `Genesys.Core` outside `App.CoreAdapter.psm1`.
- Keep auth isolated to `App.Auth.psm1` (OAuth token acquisition + DPAPI token cache only).

## Data flow and run artifacts
- UI reads Core run folders as the source of truth (`manifest.json`, `summary.json`, `events.jsonl`, `data/*.jsonl`).
- `App.UI.ps1` starts extraction in a background runspace, then polls synchronized state with `DispatcherTimer`.
- `App.Index.psm1` builds `index.jsonl` and pages with byte offsets (`FileStream.Seek`) for O(pageSize)-style retrieval.
- `App.Export.psm1` streams CSV from JSONL via `StreamReader`; avoid full in-memory dataset loading.

## Developer workflows in this repo
- Run app locally: `pwsh -NoProfile -File ./App.ps1` (PowerShell 5.1 compatibility is required).
- Compliance + architecture checks: `pwsh -NoProfile -File ./tests/Invoke-AllTests.ps1`.
- Gate D only: `pwsh -NoProfile -File ./tests/Test-Compliance.ps1`.
- App config persists to `%LOCALAPPDATA%/GenesysConversationAnalysis/config.json` (`App.Config.psm1`).
- Core/cat/schema paths can be overridden via env vars:
	- `GENESYS_CORE_MODULE`
	- `GENESYS_CORE_CATALOG`
	- `GENESYS_CORE_SCHEMA`

## Code patterns to follow
- Keep modules focused by responsibility:
	- `App.UI.ps1` = event wiring + UI state only.
	- `App.CoreAdapter.psm1` = Core invocation and run artifact access.
	- `App.Index.psm1` = indexing + paging/search primitives.
	- `App.Export.psm1` = flattening and export transforms.
- For large files (`events.jsonl`, `data/*.jsonl`), prefer streaming readers/writers; avoid `Get-Content` in hot paths.
- Preserve existing control names and bindings from `XAML/MainWindow.xaml`; UI logic expects those exact names.
- Keep run-folder compatibility stable: if you add fields, do not break existing `manifest/summary/events/data/index` handling.

## When making changes
- If a change touches Core integration/auth/compliance boundaries, update or add checks in `tests/Test-Compliance.ps1`.
- Prefer minimal edits that maintain Gate A/B/D/E intent documented in code comments and test scripts.
