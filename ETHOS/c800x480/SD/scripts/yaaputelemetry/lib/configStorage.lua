local configStorage = {}

local status = nil
local libs = nil

local MAX_SNAPSHOTS = 50
local storagePrefix = nil
local configDir = nil
local initFile = nil
local indexFile = nil

-- keys that hold Ethos source objects → serialized by name
local SOURCE_KEYS = {
  battery1Source=true, battery2Source=true,
  linkQualitySource=true, linkStatusSource2=true,
  linkStatusSource3=true, linkStatusSource4=true,
  gpsSource=true, mapZoomAdjustment=true,
}

-- derived/computed keys that are recalculated by applyConfig() → not persisted
local SKIP_KEYS = {
  horSpeedLabel=true, horSpeedMultiplier=true,
  vertSpeedLabel=true, vertSpeedMultiplier=true,
  distUnitLabel=true, distUnitLongLabel=true,
  distUnitScale=true, distUnitLongScale=true,
  mapType=true, mapZoomMax=true, mapZoomMin=true,
  mapTilesStoragePathPrefix=true, language=true,
  mapZoomCalc=true,
}

local function readFile(path)
  local f = io.open(path, "r")
  if f == nil then return nil end
  local lines = {}
  local line = f:read("l")
  while line ~= nil do
    lines[#lines+1] = line
    line = f:read("l")
  end
  f:close()
  return table.concat(lines, "\n")
end

local function detectPrefix()
  -- SD card: check if init file already exists there
  local f = io.open("SD:/scripts/yaaputelemetry/config/config.json", "r")
  if f ~= nil then f:close(); return "SD:" end
  -- SD card: probe by attempting a write
  io.mkdir("SD:/scripts/yaaputelemetry/config")
  f = io.open("SD:/scripts/yaaputelemetry/config/.probe", "w")
  if f ~= nil then f:close(); return "SD:" end
  -- fall back to internal storage
  io.mkdir("RADIO:/scripts/yaaputelemetry/config")
  return "RADIO:"
end

-- serialize one value to JSON
local function jsonValue(key, v)
  if SOURCE_KEYS[key] then
    if v == nil then return "null" end
    local ok, name = pcall(function() return v:name() end)
    return (ok and name ~= nil) and ('"__src__:' .. name .. '"') or "null"
  end
  local t = type(v)
  if t == "nil"     then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number"  then return tostring(v) end
  if t == "string"  then
    return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  return "null"
end

local function serialize(conf, widgetConf)
  local lines = {"{"}
  -- widget-level settings
  for _, k in ipairs({"screen","centerPanelIndex","leftPanelIndex","rightPanelIndex"}) do
    lines[#lines+1] = string.format('  "%s": %s,', k, jsonValue(k, widgetConf[k]))
  end
  -- conf settings (sorted for readability)
  local keys = {}
  for k in pairs(conf) do
    if not SKIP_KEYS[k] then keys[#keys+1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    lines[#lines+1] = string.format('  "%s": %s,', k, jsonValue(k, conf[k]))
  end
  -- remove trailing comma from last real entry
  if #lines > 1 then
    lines[#lines] = lines[#lines]:sub(1, -2)
  end
  lines[#lines+1] = "}"
  return table.concat(lines, "\n")
end

-- minimal JSON value parser (flat objects only, no arrays/nesting)
local function parseValue(s)
  s = s:match("^%s*(.-)%s*$")
  if s == "null"  then return nil   end
  if s == "true"  then return true  end
  if s == "false" then return false end
  local n = tonumber(s)
  if n ~= nil then return n end
  local str = s:match('^"(.*)"$')
  if str ~= nil then
    return str:gsub('\\"', '"'):gsub('\\\\', '\\')
  end
  return nil
end

local function deserialize(jsonStr)
  local result = {}
  for line in jsonStr:gmatch("[^\n]+") do
    local key, val = line:match('^%s*"([^"]+)"%s*:%s*(.-)%s*,?%s*$')
    if key ~= nil and val ~= nil then
      result[key] = parseValue(val)
    end
  end
  return result
end

local function restoreSources(conf)
  for key in pairs(SOURCE_KEYS) do
    local v = conf[key]
    if type(v) == "string" and v:sub(1, 7) == "__src__:" then
      local name = v:sub(8)
      conf[key] = system.getSource({name=name})
    end
  end
end

local function readIndex()
  local content = readFile(indexFile)
  if content == nil then return {} end
  local list = {}
  for fname in content:gmatch('"([^"]+)"') do
    list[#list+1] = fname
  end
  return list
end

local function writeIndex(list)
  local f = io.open(indexFile, "w")
  if f == nil then return end
  f:write("[\n")
  for i, fname in ipairs(list) do
    f:write('  "' .. fname .. '"' .. (i < #list and "," or "") .. "\n")
  end
  f:write("]\n")
  f:close()
end

-- public API

function configStorage.init(s, l)
  status = s
  libs = l
  storagePrefix = detectPrefix()
  configDir  = storagePrefix .. "/scripts/yaaputelemetry/config"
  initFile   = configDir .. "/config.json"
  indexFile  = configDir .. "/config_index.json"
end

function configStorage.hasInitFile()
  local f = io.open(initFile, "r")
  if f ~= nil then f:close(); return true end
  return false
end

function configStorage.readInitFile(widget)
  local content = readFile(initFile)
  if content == nil or #content < 2 then return false end
  local data = deserialize(content)
  -- widget-level settings
  if data.screen            ~= nil then widget.screen            = data.screen            end
  if data.centerPanelIndex  ~= nil then widget.centerPanelIndex  = data.centerPanelIndex  end
  if data.leftPanelIndex    ~= nil then widget.leftPanelIndex    = data.leftPanelIndex    end
  if data.rightPanelIndex   ~= nil then widget.rightPanelIndex   = data.rightPanelIndex   end
  -- conf settings
  for k, v in pairs(data) do
    if status.conf[k] ~= nil or SOURCE_KEYS[k] then
      status.conf[k] = v
    end
  end
  restoreSources(status.conf)
  return true
end

function configStorage.writeInitFile(widget)
  local f = io.open(initFile, "w")
  if f == nil then return false end
  f:write(serialize(status.conf, widget))
  f:close()
  return true
end

function configStorage.writeSnapshot(widget)
  local ts = os.date("%Y-%m-%d_%H-%M-%S")
  local fname = "config_" .. ts .. ".json"
  local snapPath = configDir .. "/" .. fname
  -- prepend snapshot timestamp as first field
  local body = serialize(status.conf, widget)
  local json = '{\n  "__snapshot__": "' .. ts .. '",' .. body:sub(2)
  local f = io.open(snapPath, "w")
  if f == nil then return end
  f:write(json)
  f:close()
  -- update index and prune oldest over limit
  local list = readIndex()
  list[#list+1] = fname
  while #list > MAX_SNAPSHOTS do
    pcall(function() os.remove(configDir .. "/" .. list[1]) end)
    table.remove(list, 1)
  end
  writeIndex(list)
end

function configStorage.getStorageLabel()
  return storagePrefix == "SD:" and "SD card" or "internal storage"
end

return configStorage
