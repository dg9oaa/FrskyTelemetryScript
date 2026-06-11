# Changes

## feat: physical zoom control via dial/knob (dg9oaa)

**File:** `../main.lua`
**Function:** `checkZoomAdjustment()`
**Target:** ETHOS c800x480 (FrSky X20S and compatible)

### What it does

Allows controlling the GMapCatcher map zoom level with a physical dial, knob, or
slider on the transmitter. The selected input source (value range −100…+100) is
linearly mapped to the available zoom levels. When the zoom level changes, the
transmitter plays haptic feedback so the pilot feels each step without looking at
the screen.

### Configuration

In the widget configuration menu a new field **"Zoom adjustment source"** appears
below "Enable map grid". Assign any analogue source (pot, slider, channel) to it.
The zoom range used for mapping is determined by the existing **GMapCatcher zoom min**
and **GMapCatcher zoom max** settings.

Leave the field empty (nil) to disable the feature — zoom then works as before
(touch/menu only).

### How the mapping works

```
source range:  -100 ──────────────────────── +100
zoom range:    gmapZoomMin ──────────── gmapZoomMax
step size:     200 // (number_of_steps - 1)   [integer division]
tolerance:     ± 5 source units per step
```

Example with gmapZoomMin = −2, gmapZoomMax = 17 (20 levels):

| Source value | Zoom level |
|---|---|
| −100 | −2 |
| −89  | −1 |
| −79  |  0 |
| …    | … |
| +100 | 17 |

### Implementation notes

- `status.conf.mapZoomCalc` caches the calculated step count and step size.
  It is reset to `false` whenever the zoom source is changed in the config or
  when the config is saved, so the next `wakeup` cycle recalculates correctly.
- The mapping loop exits on the first matching step (`break`) to avoid setting
  the zoom level more than once when two consecutive steps are both within
  tolerance of the source value.
- Haptic feedback (`system.playHaptic(150)`) fires only when the zoom level
  actually changes, not on every wakeup cycle.

### Files changed

| File | Change |
|---|---|
| `main.lua` | `status.conf`: added `mapZoomAdjustment`, `mapZoomCalc` |
| `main.lua` | `status`: added `mapZoomSteps`, `mapZoomRange` |
| `main.lua` | added `checkZoomAdjustment()` function |
| `main.lua` | `task1`: added `checkZoomAdjustment()` call (5 Hz) |
| `main.lua` | `configure()`: added "Zoom adjustment source" field |
| `main.lua` | `read()` / `write()`: persistence via `storage.*` |

### Known limitations

- Works with **GMapCatcher only**. The Google Maps provider uses a different
  zoom range and does not benefit from this feature yet.
- Not yet ported to the c480x272 and c480x320 ETHOS variants.
