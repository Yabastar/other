peripheral.find("modem", rednet.open)

rednet.host("AXNAT", "AXN Server 1")

while true do
	sleep(0.1)
	local id, message = rednet.receive()
	print("Connection to " .. id)
	if message == "page1" then
		rednet.send(id, "Hello from rednet!")
		print("Client accessed page1")
	end
end
