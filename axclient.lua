peripheral.find("modem", rednet.open)
rednet.send(38, "page1")
local id, message = rednet.receive()
print(message)
