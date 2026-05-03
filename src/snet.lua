local expect = require("cc.expect")

local random = require("ccryptolib.random")
local aead = require("ccryptolib.aead")

local MESSAGE_VALIDITY_TIME = 150 -- (ms)

local seed = ""
-- this isnt exactly secure, but its fine, probably..
for i=1,256 do
  seed = seed .. string.char(math.random(0, 255))
end

random.init(seed)
random.initWithTiming()

local function sleepFor(ms)
  local startTime = os.epoch("utc")
  local endTime = startTime + ms
  while true do
    if os.epoch("utc") > endTime then
      return
    end
    sleep()
  end
end

local function randomHex(bytes)
  local str = ""
  for i=1,bytes do
    str = str .. string.format("%02x", string.byte(random.random(1)))
  end
  return str
end


local receivedCache = {}

local function encrypt(key, message, targetAD)
  local AD = string.pack(">I8", os.epoch("utc"))..(targetAD or "")

  local nonce = random.random(12)
  local ciphertext, tag = aead.encrypt(key, nonce, message, AD)

  return string.pack(">c4sc12c16s", "SNv2", AD, nonce, tag, ciphertext)
end

local function decrypt(key, message, targetFilter)
  local s, res = pcall(function()
    local magic, AD, nonce, tag, ciphertext = string.unpack(">c4sc12c16s", message)
    assert(#AD >= 8)

    local messageTimestamp = string.unpack(">I8", AD)
    local targetAD = AD:sub(9)

    assert(magic == "SNv2")
    assert(#targetAD == 0 or targetAD == targetFilter)

    local currTimestamp = os.epoch("utc")
    assert(messageTimestamp <= currTimestamp)
    assert(currTimestamp - messageTimestamp < MESSAGE_VALIDITY_TIME)

    assert(receivedCache[nonce] == nil)
    receivedCache[nonce] = messageTimestamp

    local decryptedMessage = aead.decrypt(key, nonce, tag, ciphertext, AD)
    if decryptedMessage then
      return decryptedMessage
    else
      return nil
    end
  end)

  if s then
    return res
  else
    return nil
  end
end

return function(modem, channel, key, myName, maxModemMsgSize)
  expect(1, modem, "table")
  expect(2, channel, "number")
  expect(3, key, "string")
  expect(4, myName, "string", "nil")
  expect(5, maxModemMsgSize, "number", "nil")

  local eventID = randomHex(16)

  maxModemMsgSize = maxModemMsgSize or 65535 -- hopefully helps avoid others DOSing us, a bit at least

  local modemName = peripheral.getName(modem)
  modem.open(channel)

  sleepFor(MESSAGE_VALIDITY_TIME + 25) -- sleep to make sure that all messages that we havent been able to cache have already been invalidated (with some margin)

  return {
    receive = function(timeout)
      expect(1, timeout, "number", "nil")

      local timer
      if timeout then
        timer = os.startTimer(timeout)
      end

      while true do
        local ev = {os.pullEvent()}
        if ev[1] == "snet_message_"..eventID then
          return ev[2]
        elseif ev[1] == "timer" then
          if ev[2] == timer then
            return nil
          end
        end
      end
    end,
    send = function(message, target)
      expect(1, message, "string")
      expect(2, target, "string", "nil")

      if target then
        assert(#target > 0, "Target has to be longer than 0 characters")
      end

      modem.transmit(channel, channel, encrypt(key, message, target))
    end,
    run = function()
      parallel.waitForAny(function()
        while true do
          local currTime = os.epoch("utc")
          for k,v in pairs(receivedCache) do
            if v + MESSAGE_VALIDITY_TIME + 100 < currTime then
              receivedCache[k] = nil
            end
          end
          sleep(1)
        end
      end, function()
        while true do
          local _, side, rxChannel, _, message = os.pullEvent("modem_message")

          if side == modemName and rxChannel == channel and type(message) == "string" and #message <= maxModemMsgSize then
            local decrypted = decrypt(key, message, myName)

            if decrypted then
              os.queueEvent("snet_message_"..eventID, decrypted)
            end
          end
        end
      end)
    end
  }
end
