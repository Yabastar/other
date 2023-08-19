peripheral.find("modem", rednet.open)

rednet.host("AXNAT", "AXN Server 1")

while true do
	sleep(0.1)
	local id, message = rednet.receive()
	if message == "page1"
		rednet.send(id, "Hello from rednet!")
	end
end
