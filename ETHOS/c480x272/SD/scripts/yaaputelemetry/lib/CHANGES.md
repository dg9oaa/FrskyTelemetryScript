# Changes

## fix: GMapCatcher tile path — integer division (dg9oaa)

**File:** `maplib.lua`
**Function:** `gmapcatcher_tiles_to_path`

### Problem

In Lua 5.3+ the `/` operator always returns a float. The tile path calculation used `/` to divide tile coordinates by 1024:

```lua
-- before
string.format("...%.0f...", tile_x/1024, ...)
```

`%.0f` formats a float rounded to zero decimal places. This means values like `tile_x = 3584` produce `3584/1024 = 3.5`, which `%.0f` rounds up to `4` instead of the correct value `3`. The resulting tile path does not exist in the GMapCatcher cache and the map tile cannot be loaded.

### Fix

Replace `/` with `//` (floor integer division):

```lua
-- after
string.format("...%.0f...", tile_x//1024, ...)
```

`//` always returns an integer (truncated toward negative infinity), which is the correct behaviour for addressing GMapCatcher tile directory structures.

### Affected variants

This fix was applied to all screen-resolution variants:

| Variant | Path |
|---|---|
| ETHOS c480x272 | `ETHOS/c480x272/SD/scripts/yaaputelemetry/lib/maplib.lua` |
| ETHOS c480x320 | `ETHOS/c480x320/SD/scripts/yaaputelemetry/lib/maplib.lua` |
| ETHOS c800x480 | `ETHOS/c800x480/SD/scripts/yaaputelemetry/lib/maplib.lua` |
| OTX/ETX c320x480 | `OTX_ETX/c320x480/SD/WIDGETS/yaapu/lib/maplib.lua` |
| OTX/ETX c480x272 | `OTX_ETX/c480x272/SD/WIDGETS/yaapu/lib/maplib.lua` |
| OTX/ETX c480x320 | `OTX_ETX/c480x320/SD/WIDGETS/yaapu/lib/maplib.lua` |
| OTX/ETX c800x480 | `OTX_ETX/c800x480/SD/WIDGETS/yaapu/lib/maplib.lua` |
