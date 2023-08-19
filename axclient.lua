peripheral.find("modem", rednet.open)
print("Server to connect to: ")
server = read()
if server == "example" then
  rednet.send(38, "page1")
end
local id, message = rednet.receive()
print(message)
