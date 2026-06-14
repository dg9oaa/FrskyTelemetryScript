local configStorage = {}

local status = nil
local libs = nil

local MAX_SNAPSHOTS = 50
local storagePrefix = nil
local configDir = nil

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

local function sanitizeModelName(name)
  return (name:gsub("[^%w%-]", "_"):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

local function getInitFile()
  return configDir .. "/config_" .. sanitizeModelName(model.name()) .. ".json"
end

local function getIndexFile()
  return configDir .. "/index_" .. sanitizeModelName(model.name()) .. ".json"
end

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
  -- probe SD card by attempting a write (directory must already exist)
  local f = io.open("SD:/scripts/yaaputelemetry/config/.probe", "w")
  if f ~= nil then
    f:close()
    pcall(function() os.remove("SD:/scripts/yaaputelemetry/config/.probe") end)
    return "SD:"
  end
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

local function serializeFlat(data)
  local keys = {}
  for k in pairs(data) do keys[#keys+1] = k end
  table.sort(keys)
  local lines = {"{"}
  for i, k in ipairs(keys) do
    local comma = (i < #keys) and "," or ""
    lines[#lines+1] = string.format('  "%s": %s%s', k, jsonValue(k, data[k]), comma)
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
  local content = readFile(getIndexFile())
  if content == nil then return {} end
  local list = {}
  for fname in content:gmatch('"([^"]+)"') do
    list[#list+1] = fname
  end
  return list
end

local function writeIndex(list)
  local f = io.open(getIndexFile(), "w")
  if f == nil then return end
  f:write("[\n")
  for i, fname in ipairs(list) do
    f:write('  "' .. fname .. '"' .. (i < #list and "," or "") .. "\n")
  end
  f:write("]\n")
  f:close()
end

local function buildData(widget)
  local data = {}
  for k, v in pairs(status.conf) do
    if not SKIP_KEYS[k] then data[k] = v end
  end
  local idx = tostring(widget.instanceIndex or 1)
  local p = "instance_" .. idx .. "_"
  data[p .. "screen"]           = widget.screen
  data[p .. "centerPanelIndex"] = widget.centerPanelIndex
  data[p .. "leftPanelIndex"]   = widget.leftPanelIndex
  data[p .. "rightPanelIndex"]  = widget.rightPanelIndex
  return data
end

-- public API

function configStorage.init(s, l)
  status = s
  libs = l
  storagePrefix = detectPrefix()
  configDir = storagePrefix .. "/scripts/yaaputelemetry/config"
end

function configStorage.hasInitFile()
  local f = io.open(getInitFile(), "r")
  if f ~= nil then f:close(); return true end
  return false
end

function configStorage.readInitFile(widget)
  local content = readFile(getInitFile())
  if content == nil or #content < 2 then return false end
  local data = deserialize(content)
  -- apply conf settings
  for k, v in pairs(data) do
    if status.conf[k] ~= nil or SOURCE_KEYS[k] then
      status.conf[k] = v
    end
  end
  restoreSources(status.conf)
  -- apply this instance's screen settings
  local idx = tostring(widget.instanceIndex or 1)
  local p = "instance_" .. idx .. "_"
  if data[p .. "screen"]           ~= nil then widget.screen           = data[p .. "screen"]           end
  if data[p .. "centerPanelIndex"] ~= nil then widget.centerPanelIndex = data[p .. "centerPanelIndex"] end
  if data[p .. "leftPanelIndex"]   ~= nil then widget.leftPanelIndex   = data[p .. "leftPanelIndex"]   end
  if data[p .. "rightPanelIndex"]  ~= nil then widget.rightPanelIndex  = data[p .. "rightPanelIndex"]  end
  return true
end

function configStorage.writeInitFile(widget)
  -- read existing JSON to preserve other instances' settings
  local data = {}
  local existing = readFile(getInitFile())
  if existing ~= nil and #existing >= 2 then
    data = deserialize(existing)
  end
  -- update conf keys
  for k, v in pairs(status.conf) do
    if not SKIP_KEYS[k] then data[k] = v end
  end
  -- update this instance's screen settings
  local idx = tostring(widget.instanceIndex or 1)
  local p = "instance_" .. idx .. "_"
  data[p .. "screen"]           = widget.screen
  data[p .. "centerPanelIndex"] = widget.centerPanelIndex
  data[p .. "leftPanelIndex"]   = widget.leftPanelIndex
  data[p .. "rightPanelIndex"]  = widget.rightPanelIndex
  -- write
  local f = io.open(getInitFile(), "w")
  if f == nil then return false end
  f:write(serializeFlat(data))
  f:close()
  return true
end

function configStorage.writeSnapshot(widget)
  local modelName = sanitizeModelName(model.name())
  local ts = os.date("%Y-%m-%d_%H-%M-%S")
  local fname = "config_" .. modelName .. "_" .. ts .. ".json"
  local snapPath = configDir .. "/" .. fname
  local data = buildData(widget)
  data["__model__"]    = model.name()
  data["__snapshot__"] = ts
  local f = io.open(snapPath, "w")
  if f == nil then return end
  f:write(serializeFlat(data))
  f:close()
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
