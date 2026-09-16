-- Log in and drive the machine from its own keyboard, with no window.
--
--   mame noname -video none -autoboot_script keyboard.lua ...
--
-- The screen is read back through the bus rather than rendered, so this works
-- headless and the guest's own output is what decides when to type next.

local COMMANDS = {
	{ "root", 180 },
	{ "uname -a", 240 },
	{ "echo it-works", 300 },
	{ "sync", 300 },
}

local space = manager.machine.devices[":cpu"].spaces["2"]
local TEXT = 0x01700000   -- the text buffer, through the sparse pci window
local WINDOW = 0x8000     -- the whole text window, because the console scrolls
                          -- by moving the crtc start address
local step = 0
local waited = 0

local function say(message)
	print("[lua] " .. message)
	io.stdout:flush()
end

-- sparse addressing puts the byte in the lane the low address bits select, so
-- the longword has to be read and the byte taken out of it
local function screen()
	local parts = {}
	for address = 0, WINDOW - 2, 2 do
		local value = space:read_u32(TEXT + address * 32)
		local char = (value >> ((address % 4) * 8)) & 0xff
		parts[#parts + 1] = (char >= 32 and char < 127) and string.char(char) or " "
	end
	return table.concat(parts)
end

local function dump()
	say("---- screen ----")
	local all = screen()
	for start = 1, #all, 80 do
		local row = all:sub(start, start + 79):gsub("%s+$", "")
		if #row > 0 then print(row) end
	end
	say("---- end of screen ----")
	io.stdout:flush()
end

local function tick()
	waited = waited + 1

	if step == 0 then
		if waited % 60 ~= 0 then return end
		if screen():find("login:") then
			manager.machine.natkeyboard.in_use = true
			say("login prompt found")
			step = 1
			waited = 0
		end
		return
	end

	if step <= #COMMANDS then
		if waited < (step == 1 and 120 or COMMANDS[step - 1][2]) then return end
		emu.keypost(COMMANDS[step][1] .. "\n")
		say("typed: " .. COMMANDS[step][1])
		step = step + 1
		waited = 0
		return
	end

	if waited == COMMANDS[#COMMANDS][2] then
		dump()
		manager.machine:exit()
	end
end

subscription = emu.add_machine_frame_notifier(tick)
say("keyboard script loaded")
