# Config JSON Storage — CHANGES

## Feature: JSON-based configuration file storage

### Summary

Adds persistent JSON config file storage alongside the existing Ethos `storage.read()`/`storage.write()` mechanism.
The config is written to and read from a flat JSON file (`config.json`), with automatic SD card detection and a
snapshot history of up to 50 entries.

### Files changed

- `lib/configStorage.lua` — **new file**, implements the full storage module
- `main.lua` — integrates configStorage into the widget lifecycle

---

### configStorage.lua

New library module loaded via `loadLib("configStorage")`.

**SD card detection (`detectPrefix`):**
Checks `SD:/scripts/yaaputelemetry/config/config.json` first (init file already there → SD card).
If not found, probes by attempting a write to `SD:/scripts/yaaputelemetry/config/.probe`.
Falls back to `RADIO:` (internal storage) if SD card is not writable.

**Serialization:**
- Flat JSON, one key per line, keys sorted alphabetically for readable diffs.
- Derived/computed keys are excluded via `SKIP_KEYS` (e.g. `horSpeedLabel`, `mapZoomCalc`).
- Ethos source objects (userdata) are serialized as `"__src__:<name>"` using `v:name()`,
  and restored with `system.getSource({name=name})`.

**Init file** (`config.json`):
Written on demand (manual button in configure menu or on write).
Read on startup via `read()` — takes priority over `storage.read()` values.

**Snapshots** (`config_<timestamp>.json`):
Written automatically at widget startup if the init file already exists (i.e. not the very first run).
Timestamps in `YYYY-MM-DD_HH-MM-SS` format.
An index file (`config_index.json`) tracks the list; oldest entries are pruned when the limit of 50 is exceeded.

**Public API:**

| Function | Description |
|---|---|
| `init(status, libs)` | Initializes module, detects storage prefix |
| `hasInitFile()` | Returns true if `config.json` exists |
| `readInitFile(widget)` | Reads and applies `config.json` to `status.conf` and widget fields |
| `writeInitFile(widget)` | Serializes and writes `status.conf` + widget fields to `config.json` |
| `writeSnapshot(widget)` | Writes a timestamped snapshot; updates index; prunes if > 50 |
| `getStorageLabel()` | Returns `"SD card"` or `"internal storage"` |

---

### main.lua changes

- `initLibs()`: loads `configStorage` library.
- `read()`: reads JSON init file first (if it exists), then falls through to `storage.read()` for any values
  not present in the JSON. This ensures backward compatibility with existing Ethos storage.
- `write()`: writes JSON init file after the normal `storage.write()` call.
- `createOnce()`: writes a snapshot at widget startup if the init file already exists.
- `configure()`: adds a **"Save config to file"** button at the bottom of the configuration form,
  showing which storage location is active (SD card or internal). Pressing it writes the init file immediately
  and confirms via a push message.

---

### Known limitations / future work

- Only implemented for `ETHOS/c800x480`. Other variants (`c480x272`, `c480x320`) to follow once the
  concept is confirmed stable.
- No UI to browse or restore individual snapshots — snapshots are for manual forensics only (copy off SD card).
- The `mapZoomAdjustment` source key is in `SOURCE_KEYS` but only exists on branches that include
  `feat/zoom-adjustment-knob`. On `master`-based builds it will simply be skipped (value is `nil` → serialized
  as `null`, ignored on read).
