local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TAP_SUBS_MSG = 0x10
TEXT_MSG = 0x12

-- Frame to Phone flags
TAP_MSG = 0x09

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TAP_SUBS_MSG] = code.parse_code
data.parsers[TEXT_MSG] = plain_text.parse_plain_text

function handle_tap()
	pcall(frame.bluetooth.send, string.char(TAP_MSG))
end

-- Main app loop
function app_loop()
	-- clear the display
	frame.display.text(" ", 1, 1)
	frame.display.show()
    local last_batt_update = 0

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				local i = 0
				for line in data.app_data[TEXT_MSG].string:gmatch("([^\n]*)\n?") do
					if line ~= "" then
						frame.display.text(line, 1, i * 60 + 1)
						i = i + 1
					end
				end
				frame.display.show()
			end

			if (data.app_data[TAP_SUBS_MSG] ~= nil) then

				if data.app_data[TAP_SUBS_MSG].value == 1 then
					-- start subscription to tap events
					frame.imu.tap_callback(handle_tap)
				else
					-- cancel subscription to tap events
					frame.imu.tap_callback(nil)
				end

				data.app_data[TAP_SUBS_MSG] = nil
			end

		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()
