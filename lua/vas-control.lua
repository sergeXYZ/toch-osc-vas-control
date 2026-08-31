-- VAS CONTROL 1.0 — Spezial Presets behaviour (En-Space Input Bank)
-- TouchOSC → DS100: Send Port 50010, Receive Port 50011 (DS100 replies on 50011).
-- Prefix: /dbaudio1

local PREFIX = '/dbaudio1'
local MAX_INPUT_COUNT = 128
local GAIN_MIN = -120.0
local GAIN_MAX = 24.0
local ZONE_ON_DB = 0.0
local ZONE_OFF_DB = -120.0
local ZONE_ON_THRESHOLD = -60.0
local POLL_CONTINUOUS_MS = 500
local POLL_DISCRETE_MS = 2000

local ZONE_NAMES = {
  'Zone 1 - left',
  'Zone 2 - center',
  'Zone 3 - right',
  'Zone 4 - audience',
}

local INPUT_DEC_NAMES = { 'inputDec', 'button2', 'Input Dec', 'Input -' }
local INPUT_INC_NAMES = { 'inputInc', 'button1', 'Input Inc', 'Input +' }

local ui = {}
local zoneOnColor = {
  Color(0, 0, 1),
  Color(1, 0, 1),
  Color(1, 0, 0),
  Color(0, 1, 0),
}
local zoneOffColor = Color(0.4, 0.4, 0.4)

local selectedInput = 1
local inputCount = MAX_INPUT_COUNT
local sendGain = nil
local zoneGain = { nil, nil, nil, nil }
local inputName = nil
local pollRxCount = 0

local lastContinuous = 0
local lastDiscrete = 0
local lastZoneDown = { false, false, false, false }
local lastInputDecDown = false
local lastInputIncDown = false
local lastAllSendDown = false
local lastAllZonesDown = false
local lastEncoderX = nil
local updatingFader = false
local updatingEncoder = false

local selectInput

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function normalizePath(path)
  if type(path) ~= 'string' then
    return nil
  end
  path = string.gsub(path, '/+$', '')
  return path
end

local function splitPath(path)
  local parts = {}
  for seg in string.gmatch(path or '', '[^/]+') do
    parts[#parts + 1] = seg
  end
  return parts
end

local function pathIndex(parts, pos)
  if parts == nil or parts[pos] == nil then
    return nil
  end
  return tonumber(parts[pos])
end

local function xToDb(x)
  x = clamp(x, 0, 1)
  if x >= 0.75 then
    return (x - 0.75) / 0.25 * GAIN_MAX
  elseif x >= 0.5 then
    return x * 40.0 - 30.0
  elseif x >= 0.25 then
    return x * 80.0 - 50.0
  elseif x >= 0.0625 then
    return x * 160.0 - 70.0
  end
  return x * 960.0 + GAIN_MIN
end

local function dbToX(db)
  if db == nil then return 0 end
  db = clamp(db, GAIN_MIN, GAIN_MAX)
  if db < -60.0 then
    return (db - GAIN_MIN) / 960.0
  elseif db < -30.0 then
    return (db + 70.0) / 160.0
  elseif db < -10.0 then
    return (db + 50.0) / 80.0
  elseif db < 0.0 then
    return (db + 30.0) / 40.0
  end
  return 0.75 + db / GAIN_MAX * 0.25
end

local function formatDb(db)
  if db == nil then return '—' end
  local s = string.format('%.1f', db)
  s = string.gsub(s, '%.', ',')
  return s .. ' dB'
end

local function zoneIsOn(db)
  return db ~= nil and db > ZONE_ON_THRESHOLD
end

local function child(name)
  return self.children[name]
end

local function findChild(names)
  for i = 1, #names do
    local c = child(names[i])
    if c then return c end
  end
  return nil
end

local function setText(ctrl, text)
  if ctrl then
    ctrl.values.text = text
  end
end

local function sendFloat(path, value)
  sendOSC({
    path,
    { { tag = 'f', value = value } },
  })
end

local function queryRead(path)
  sendOSC({ path, {} })
end

local function oscStringArg(arguments)
  if arguments == nil then return nil end
  for i = 1, #arguments do
    local a = arguments[i]
    if type(a) == 'string' then
      return a
    end
    if type(a) == 'table' and a.value ~= nil then
      local tag = a.tag
      if tag == nil or tag == 's' or tag == 'S' then
        return tostring(a.value)
      end
    end
  end
  return nil
end

local function oscNumberArg(arguments)
  if arguments == nil then return nil end
  for i = 1, #arguments do
    local a = arguments[i]
    if type(a) == 'number' then
      return a
    end
    if type(a) == 'table' and a.value ~= nil then
      local tag = a.tag
      if tag == nil or tag == 'f' or tag == 'F' or tag == 'd' or tag == 'i' or tag == 'I' or tag == 'h' then
        return tonumber(a.value)
      end
    end
  end
  return nil
end

local function numberFromPathTail(parts)
  if parts == nil or #parts < 5 then
    return nil
  end
  return tonumber(parts[#parts])
end

local function channelNameFromPath(parts)
  if parts == nil or #parts < 5 then
    return nil
  end
  if pathIndex(parts, 5) ~= nil then
    if #parts < 6 then
      return nil
    end
    return table.concat(parts, '/', 6)
  end
  return parts[5]
end

local function applyZoneColors()
  for z = 1, 4 do
    local btn = ui.zones[z]
    if btn then
      if zoneIsOn(zoneGain[z]) then
        btn.color = zoneOnColor[z]
      else
        btn.color = zoneOffColor
      end
    end
  end
end

local function syncEncoderToInput()
  if not ui.encoder or inputCount <= 1 then
    return
  end
  local x = (selectedInput - 1) / (inputCount - 1)
  updatingEncoder = true
  ui.encoder.values.x = x
  lastEncoderX = x
  updatingEncoder = false
end

local function refreshDisplays()
  setText(ui.inputNumber, tostring(selectedInput))
  if inputName ~= nil and inputName ~= '' then
    setText(ui.inputName, inputName)
  else
    setText(ui.inputName, '—')
  end
  setText(ui.sendLabel, 'En-Space\nSend gain\n' .. formatDb(sendGain))

  if ui.fader and not ui.fader.values.touch and sendGain ~= nil then
    updatingFader = true
    ui.fader.values.x = dbToX(sendGain)
    updatingFader = false
  end

  applyZoneColors()
end

local function pollContinuous()
  local n = selectedInput
  queryRead(PREFIX .. '/matrixinput/reverbsendgain/' .. n)
  queryRead(PREFIX .. '/matrixinput/channelname/' .. n)
  for z = 1, 4 do
    queryRead(PREFIX .. '/reverbinput/gain/' .. n .. '/' .. z)
  end
end

local function pollDiscrete()
  queryRead(PREFIX .. '/status/matrixinputcount')
end

local function setInputCount(n)
  n = clamp(math.floor(n + 0.5), 1, MAX_INPUT_COUNT)
  if n == inputCount then
    return
  end
  inputCount = n
  if ui.encoder then
    ui.encoder.gridSteps = inputCount
  end
  if selectedInput > inputCount then
    selectInput(inputCount)
  else
    syncEncoderToInput()
  end
end

selectInput = function(n)
  n = math.floor(n + 0.5)
  while n < 1 do n = n + inputCount end
  while n > inputCount do n = n - inputCount end
  if n == selectedInput then
    pollContinuous()
    return
  end
  selectedInput = n
  sendGain = nil
  inputName = nil
  zoneGain = { nil, nil, nil, nil }
  syncEncoderToInput()
  refreshDisplays()
  pollContinuous()
  pollDiscrete()
end

local function stepInput(delta)
  selectInput(selectedInput + delta)
end

local function encoderToInput(x)
  if inputCount <= 1 then return 1 end
  local n = math.floor(x * (inputCount - 1) + 1.5)
  return clamp(n, 1, inputCount)
end

local function applyExclusiveZone(zone, turnOn)
  local n = selectedInput
  if turnOn then
    for z = 1, 4 do
      local db = ZONE_OFF_DB
      if z == zone then db = ZONE_ON_DB end
      zoneGain[z] = db
      sendFloat(PREFIX .. '/reverbinput/gain/' .. n .. '/' .. z, db)
    end
  else
    zoneGain[zone] = ZONE_OFF_DB
    sendFloat(PREFIX .. '/reverbinput/gain/' .. n .. '/' .. zone, ZONE_OFF_DB)
  end
  applyZoneColors()
end

local function handleZonePress(zone)
  applyExclusiveZone(zone, not zoneIsOn(zoneGain[zone]))
end

local function handleAllSendOff()
  sendFloat(PREFIX .. '/matrixinput/reverbsendgain/*', ZONE_OFF_DB)
  sendGain = ZONE_OFF_DB
  refreshDisplays()
end

local function handleAllZonesOff()
  sendFloat(PREFIX .. '/reverbinput/gain/*/*', ZONE_OFF_DB)
  zoneGain = { ZONE_OFF_DB, ZONE_OFF_DB, ZONE_OFF_DB, ZONE_OFF_DB }
  applyZoneColors()
end

local function rising(now, last)
  return now and not last
end

local function pressed(ctrl)
  return ctrl ~= nil and ctrl.values.x > 0.5
end

local function handleOscMessage(message)
  if type(message) ~= 'table' then
    return false
  end

  local path = normalizePath(message[1])
  local arguments = message[2]
  if path == nil or string.sub(path, 1, #PREFIX) ~= PREFIX then
    return false
  end

  pollRxCount = pollRxCount + 1

  local parts = splitPath(path)
  local module = parts[2]
  local name = parts[3]
  local a = parts[4]
  local b = parts[5]
  local idx = pathIndex(parts, 4)
  local zone = pathIndex(parts, 5)

  if module == 'status' and name == 'matrixinputcount' then
    local n = oscNumberArg(arguments)
    if n ~= nil and n >= 1 then
      setInputCount(n)
    end
    return true
  end

  if module == 'matrixinput' and name == 'reverbsendgain' then
    if idx == selectedInput then
      local gain = oscNumberArg(arguments)
      if gain == nil then
        gain = numberFromPathTail(parts)
      end
      sendGain = gain
      refreshDisplays()
    end
    return true
  end

  if module == 'matrixinput' and name == 'channelname' then
    if idx == selectedInput then
      local str = oscStringArg(arguments)
      if str == nil or str == '' then
        str = channelNameFromPath(parts)
      end
      if str == nil or str == '' then
        inputName = nil
      else
        inputName = str
      end
      refreshDisplays()
    end
    return true
  end

  if module == 'reverbinput' and name == 'gain' then
    if idx == selectedInput and zone ~= nil and zone >= 1 and zone <= 4 then
      local gain = oscNumberArg(arguments)
      if gain == nil then
        gain = numberFromPathTail(parts)
      end
      zoneGain[zone] = gain
      applyZoneColors()
    end
    return true
  end

  return false
end

function init()
  ui.encoder = child('Input seect')
  ui.inputNumber = child('Input Number')
  ui.inputName = child('Input Name')
  ui.inputDec = findChild(INPUT_DEC_NAMES)
  ui.inputInc = findChild(INPUT_INC_NAMES)
  ui.fader = child('En-Space gain')
  ui.sendLabel = child('text6')
  ui.allSend = child('All En-Space send -120 db')
  ui.allZones = child('All Inputs - all Zones -120db')
  ui.zones = {}
  for z = 1, 4 do
    ui.zones[z] = child(ZONE_NAMES[z])
  end

  zoneOnColor[2] = Color(1, 0, 1)

  if ui.encoder then
    ui.encoder.gridSteps = inputCount
    lastEncoderX = ui.encoder.values.x
    selectedInput = encoderToInput(ui.encoder.values.x)
  end
  if ui.fader then
    ui.fader.grid = false
  end

  syncEncoderToInput()
  refreshDisplays()
  pollContinuous()
  pollDiscrete()
  lastContinuous = getMillis()
  lastDiscrete = lastContinuous
end

function update()
  local now = getMillis()

  if ui.encoder and not updatingEncoder then
    local x = ui.encoder.values.x
    if lastEncoderX == nil or math.abs(x - lastEncoderX) > 0.0001 then
      lastEncoderX = x
      selectInput(encoderToInput(x))
    end
  end

  local decDown = pressed(ui.inputDec)
  if rising(decDown, lastInputDecDown) then
    stepInput(-1)
  end
  lastInputDecDown = decDown

  local incDown = pressed(ui.inputInc)
  if rising(incDown, lastInputIncDown) then
    stepInput(1)
  end
  lastInputIncDown = incDown

  if ui.fader and ui.fader.values.touch and not updatingFader then
    local db = xToDb(ui.fader.values.x)
    if sendGain == nil or math.abs(db - sendGain) >= 0.05 then
      sendGain = db
      sendFloat(PREFIX .. '/matrixinput/reverbsendgain/' .. selectedInput, db)
      setText(ui.sendLabel, 'En-Space\nSend gain\n' .. formatDb(sendGain))
    end
  end

  for z = 1, 4 do
    local down = pressed(ui.zones[z])
    if rising(down, lastZoneDown[z]) then
      handleZonePress(z)
    end
    lastZoneDown[z] = down
  end

  local allSendDown = pressed(ui.allSend)
  if rising(allSendDown, lastAllSendDown) then
    handleAllSendOff()
  end
  lastAllSendDown = allSendDown

  local allZonesDown = pressed(ui.allZones)
  if rising(allZonesDown, lastAllZonesDown) then
    handleAllZonesOff()
  end
  lastAllZonesDown = allZonesDown

  if now - lastContinuous >= POLL_CONTINUOUS_MS then
    lastContinuous = now
    pollContinuous()
  end
  if now - lastDiscrete >= POLL_DISCRETE_MS then
    lastDiscrete = now
    pollDiscrete()
  end
end

function onReceiveOSC(message, connections)
  return handleOscMessage(message)
end

function onReceiveNotify(name, message)
  if name == 'osc' then
    return handleOscMessage(message)
  end
end
