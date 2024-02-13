local expect = dofile("rom/modules/main/cc/expect.lua").expect


_G.CHANNEL_BROADCAST = 65535

_G.CHANNEL_REPEAT = 65533

_G.rednetID = os.getComputerID()

_G.duplicate_msg = false

_G.rednet_seed = (os.time()^5)

_G.rednet_reply = os.getComputerID()

_G.override_hostname_check = false

math.randomseed(rednet_seed)

local tReceivedMessages = {}
local tReceivedMessageTimeouts = {}
local tHostnames = {}

function open(modem)
    expect(1, modem, "string")
    if peripheral.getType(modem) ~= "modem" then
        error("No such modem: " .. modem, 2)
    end
    peripheral.call(modem, "open", rednetID)
    peripheral.call(modem, "open", CHANNEL_BROADCAST)
end

function close(modem)
    expect(1, modem, "string", "nil")
    if modem then
        if peripheral.getType(modem) ~= "modem" then
            error("No such modem: " .. modem, 2)
        end
        peripheral.call(modem, "close", rednetID)
        peripheral.call(modem, "close", CHANNEL_BROADCAST)
    else
        for _, modem in ipairs(peripheral.getNames()) do
            if isOpen(modem) then
                close(modem)
            end
        end
    end
end

function isOpen(modem)
    expect(1, modem, "string", "nil")
    if modem then
        if peripheral.getType(modem) == "modem" then
            return peripheral.call(modem, "isOpen", os.getComputerID()) and peripheral.call(modem, "isOpen", CHANNEL_BROADCAST)
        end
    else
        for _, modem in ipairs(peripheral.getNames()) do
            if isOpen(modem) then
                return true
            end
        end
    end
    return false
end

function send(nRecipient, message, sProtocol)
    expect(1, nRecipient, "number")
    expect(3, sProtocol, "string", "nil")

    local nMessageID = math.random(1, 2147483647)
    tReceivedMessages[nMessageID] = duplicate_msg
    tReceivedMessageTimeouts[os.startTimer(30)] = nMessageID

    local nReplyChannel = rednet_reply
    local tMessage = {
        nMessageID = nMessageID,
        nRecipient = nRecipient,
        message = message,
        sProtocol = sProtocol,
    }

    local sent = false
    if nRecipient == rednetID then
        os.queueEvent("rednet_message", nReplyChannel, message, sProtocol)
        sent = true
    else
        for _, sModem in ipairs(peripheral.getNames()) do
            if isOpen(sModem) then
                peripheral.call(sModem, "transmit", nRecipient, nReplyChannel, tMessage)
                peripheral.call(sModem, "transmit", CHANNEL_REPEAT, nReplyChannel, tMessage)
                sent = true
            end
        end
    end

    return sent
end

function broadcast(message, sProtocol)
    expect(2, sProtocol, "string", "nil")
    send(CHANNEL_BROADCAST, message, sProtocol)
end

function receive(sProtocolFilter, nTimeout)
    if type(sProtocolFilter) == "number" and nTimeout == nil then
        sProtocolFilter, nTimeout = nil, sProtocolFilter
    end
    expect(1, sProtocolFilter, "string", "nil")
    expect(2, nTimeout, "number", "nil")

    local timer = nil
    local sFilter = nil
    if nTimeout then
        timer = os.startTimer(nTimeout)
        sFilter = nil
    else
        sFilter = "rednet_message"
    end

    while true do
        local sEvent, p1, p2, p3 = os.pullEvent(sFilter)
        if sEvent == "rednet_message" then
            local nSenderID, message, sProtocol = p1, p2, p3
            if sProtocolFilter == nil or sProtocol == sProtocolFilter then
                return nSenderID, message, sProtocol
            end
        elseif sEvent == "timer" then
            if p1 == timer then
                return nil
            end
        end
    end
end

function host(sProtocol, sHostname)
    expect(1, sProtocol, "string")
    expect(2, sHostname, "string")
    if sHostname == "localhost" then
        error("Reserved hostname", 2)
    end
    if tHostnames[sProtocol] ~= sHostname then
        if lookup(sProtocol, sHostname) ~= nil then
            if override_hostname_check == false then
                error("Hostname in use", 2)
            end
        end
        tHostnames[sProtocol] = sHostname
    end
end

function unhost(sProtocol)
    expect(1, sProtocol, "string")
    tHostnames[sProtocol] = nil
end

function lookup(sProtocol, sHostname)
    expect(1, sProtocol, "string")
    expect(2, sHostname, "string", "nil")

    local tResults = nil
    if sHostname == nil then
        tResults = {}
    end

    if tHostnames[sProtocol] then
        if sHostname == nil then
            table.insert(tResults, os.getComputerID())
        elseif sHostname == "localhost" or sHostname == tHostnames[sProtocol] then
            return os.getComputerID()
        end
    end

    if not isOpen() then
        if tResults then
            return table.unpack(tResults)
        end
        return nil
    end

    -- Broadcast a lookup packet
    broadcast({
        sType = "lookup",
        sProtocol = sProtocol,
        sHostname = sHostname,
    }, "dns")

    local timer = os.startTimer(2)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local nSenderID, tMessage, sMessageProtocol = p1, p2, p3
            if sMessageProtocol == "dns" and type(tMessage) == "table" and tMessage.sType == "lookup response" then
                if tMessage.sProtocol == sProtocol then
                    if sHostname == nil then
                        table.insert(tResults, nSenderID)
                    elseif tMessage.sHostname == sHostname then
                        return nSenderID
                    end
                end
            end
        else
            if p1 == timer then
                break
            end
        end
    end
    if tResults then
        return table.unpack(tResults)
    end
    return nil
end

local bRunning = false

function run()
    if bRunning then
        error("rednet is already running", 2)
    end
    bRunning = true

    while bRunning do
        local sEvent, p1, p2, p3, p4 = os.pullEventRaw()
        if sEvent == "modem_message" then
            local sModem, nChannel, nReplyChannel, tMessage = p1, p2, p3, p4
            if isOpen(sModem) and (nChannel == os.getComputerID() or nChannel == CHANNEL_BROADCAST) then
                if type(tMessage) == "table" and tMessage.nMessageID then
                    if not tReceivedMessages[tMessage.nMessageID] then
                        tReceivedMessages[tMessage.nMessageID] = true
                        tReceivedMessageTimeouts[os.startTimer(30)] = tMessage.nMessageID
                        os.queueEvent("rednet_message", nReplyChannel, tMessage.message, tMessage.sProtocol)
                    end
                end
            end

        elseif sEvent == "rednet_message" then
            local nSenderID, tMessage, sProtocol = p1, p2, p3
            if sProtocol == "dns" and type(tMessage) == "table" and tMessage.sType == "lookup" then
                local sHostname = tHostnames[tMessage.sProtocol]
                if sHostname ~= nil and (tMessage.sHostname == nil or tMessage.sHostname == sHostname) then
                    rednet.send(nSenderID, {
                        sType = "lookup response",
                        sHostname = sHostname,
                        sProtocol = tMessage.sProtocol,
                    }, "dns")
                end
            end

        elseif sEvent == "timer" then
            local nTimer = p1
            local nMessage = tReceivedMessageTimeouts[nTimer]
            if nMessage then
                tReceivedMessageTimeouts[nTimer] = nil
                tReceivedMessages[nMessage] = nil
            end
        end
    end
end
