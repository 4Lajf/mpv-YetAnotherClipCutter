---SETTINGS---------------------------------------------------
--------------------------------------------------------------

-- SET THE FOLDER YOU WANT BELOW - for example "C:\\Users\\you\\Desktop\\"
-- Yes it needs to have double backslash like this and end on \\ idk why
target_path = ""

-- SET YOUR FFMPEG PATHFILE same as above, for example "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe"
-- Unless you have your environment variables set, then leave as is
-- (if you don't know what any of that means: https://www.wikihow.com/Install-FFmpeg-on-Windows)
ffmpeg_bin = "ffmpeg"

-- Set the keybindings for the start and end time of the clip
-- You can type key combinations like "ctrl+j" or "alt+g" - for "shift+h" type capital "H"
-- Add the bindings to your input.conf file
-- Example:
-- Ctrl+w script-binding clipping/time-start
-- Ctrl+e script-binding clipping/time-end
-- Ctrl+c script-binding clipping/mode-swtich
-- Ctrl+x script-binding clipping/slicing-mark

-- Set your default cutting mode (by default it reencodes the file, this results in accurate cut with some usually unnoticable compression)
cut_mode = 1

-- Set the default output format (MP4 is the safest usually)
format = "mp4"

--------------------------------------------------------------
---SETTINGS END HERE------------------------------------------

-- Paths needed to create a temporary subtitle file for the process of burning-in subs
-- They get repeated later, idr why I put them twice, maybe one's redundant, should test it at some point
subtitle_path = string.gsub(target_path, "\\", "/") .. "clip_cutter_subtitle.ass"
subtitle_path = string.gsub(subtitle_path, ":", "\\:")

-- Small function used to try ensuring that subtitle file is fully rendered by the time we start making the video file
-- I should get a signal from ffmpeg when it's done instead but idk how to do that
function wait(seconds)
	local start = os.time()
	repeat until os.time() > start + seconds
end

function copyToClipboard(text)
	-- Use io.popen with the 'w' flag to write to the process' stdin
	local proc = io.popen('clip', 'w')
	if proc then
		proc:write(text)
		proc:close()
	else
		mp.msg.error("Failed to copy text to clipboard.")
	end
end

-- This function saves the timestamp for where you want your clip to begin.
function save_time_pos()
	time_pos_start = mp.get_property_number("time-pos")
	local hours = math.floor(time_pos_start / 3600)
	local minutes = math.floor((time_pos_start % 3600) / 60)
	local seconds = math.floor(time_pos_start % 60) -- Excludes fraction of a second

	-- Conditionally format timestamp_start based on whether hours are present
	if hours > 0 then
		timestamp_start = string.format("%d:%02d:%02d", hours, minutes, seconds)
	else
		timestamp_start = string.format("%02d:%02d", minutes, seconds)
	end
	mp.osd_message(string.format("Starting timestamp: %s", timestamp_start))
end

-- If you want to make a cropped clip, well, here's what takes the parameters and prepares them into ffmpeg-friendly format
function check_for_crop()
	-- I think I copied this code from another clipper, remind me to find it and check if their license permits it or if I need to get rid of this function
	-- But basically it gets the crop information from the VF applied to your player and formats it for ffmpeg VF
	filter = ""
	for _, vf in ipairs(mp.get_property_native("vf")) do
		local name = vf["name"]
		name = string.gsub(name, '^lavfi%-', '')
		if name == "crop" then
			local p = vf["params"]
			filter = string.format("crop=%d:%d:%d:%d,", p.w, p.h, p.x, p.y)
		end
	end
end

-- Crude function to select the cutting mode by scrolling through them with a key press and OSD print selected one
-- Probably due to a rewrite soon
function mode_switch()
	if cut_mode == 5 then
		cut_mode = 1
		mp.osd_message("1. MP4 reencode")
	elseif cut_mode == 1 then
		cut_mode = 2
		mp.osd_message("2. MP4 subtitle burn")
	elseif cut_mode == 2 then
		cut_mode = 3
		mp.osd_message("3. GIF resized")
	elseif cut_mode == 3 then
		cut_mode = 4
		mp.osd_message("4. GIF cropped")
	elseif cut_mode == 4 then
		cut_mode = 5
		mp.osd_message("5. MP4 copy")
	end
end

function slicing_mark()
	if time_pos_start == nil then
		save_time_pos()
	else
		clipCutter()
	end
end

function on_ffmpeg_finish(execution_finished, result, error)
	if execution_finished then
		-- Since execution_finished is true, FFmpeg command was executed, now check for FFmpeg errors in stderr
		if result.status == 0 then
			mp.osd_message("Clip successfully created")
			mp.msg.info("Clip successfully created")
		else
			-- FFmpeg encountered an error, output captured in result.stderr
			local errorMsg = "Failed to create clip. Check console for more details."
			if result.stderr and result.stderr ~= "" then
				errorMsg = errorMsg .. "\n" .. result.stderr
			end
			mp.osd_message("Failed to create clip. Check console for more details.")
			mp.msg.error(errorMsg)
		end
	else
		-- Here, success being false means the subprocess command itself failed to initialize.
		mp.osd_message("Failed to launch FFmpeg command.")
		mp.msg.error("Failed to launch FFmpeg command.")
	end

	-- Resetting time markers
	time_pos_start = nil
	time_pos_end = nil
end

-- The main function
function clipCutter()
	if time_pos_start ~= nil then
		local time_pos_end = mp.get_property_number("time-pos")
		if time_pos_end > time_pos_start then
			time_pos_end = mp.get_property_number("time-pos")
			local hours = math.floor(time_pos_end / 3600)
			local minutes = math.floor((time_pos_end % 3600) / 60)
			local seconds = math.floor(time_pos_end % 60) -- Excludes fraction of a second

			-- Conditionally format timestamp_start based on whether hours are present
			if hours > 0 then
				timestamp_end = string.format("%d:%02d:%02d", hours, minutes, seconds)
			else
				timestamp_end = string.format("%02d:%02d", minutes, seconds)
			end

			mp.osd_message(string.format("Making clip from %s to %s", timestamp_start, timestamp_end))

			-- Mapping logic including video, audio, and potential subtitles
			local mapping_args = {}
			local audio_id = mp.get_property_number("current-tracks/audio/id")
			local video_id = mp.get_property_number("current-tracks/video/id")
			local sub_id = mp.get_property_number("current-tracks/sub/id")

			if video_id then
				table.insert(mapping_args, "-map")
				table.insert(mapping_args, string.format("0:v:%d", video_id - 1))
			end

			if audio_id then
				table.insert(mapping_args, "-map")
				table.insert(mapping_args, string.format("0:a:%d", audio_id - 1))
			end

			if sub_id then
				table.insert(mapping_args, "-map")
				table.insert(mapping_args, string.format("0:s:%d", sub_id - 1))
				table.insert(mapping_args, "-c:s")
				table.insert(mapping_args, "mov_text") -- Ensure compatibility, change if needed.
			end

			-- Add general mapping attributes
			table.insert(mapping_args, "-map_chapters")
			table.insert(mapping_args, "-1")
			table.insert(mapping_args, "-map_metadata")
			table.insert(mapping_args, "-1")

			mp.osd_message(string.format("Making clip from %s to %s", timestamp_start, timestamp_end))
			time_pos_end = time_pos_end - time_pos_start

			if cut_mode == 1 then
				local timestamp_start_dotted = timestamp_start:gsub(":", ".")
				local timestamp_end_dotted = timestamp_end:gsub(":", ".")
				local output_filename = string.format("%s_%s_%s.%s",
					mp.get_property("filename/no-ext"), timestamp_start_dotted, timestamp_end_dotted, "mp4")

				-- Assemble the FFmpeg command
				local command = {
					name = "subprocess",
					playback_only = false,
					capture_stdout = true,
					capture_stderr = true,
					args = {
						ffmpeg_bin, "-y", "-v", "error", "-hide_banner", "-stats",
						"-ss", tostring(time_pos_start),
						"-i", mp.get_property("path"), "-avoid_negative_ts", "make_zero",
						"-t", tostring(time_pos_end),
						"-c:v", "libx264", "-c:a", "copy", "-pix_fmt", "yuv420p"
					}
				}

				-- Insert mapping args and output filename into command args
				for _, arg in ipairs(mapping_args) do
					table.insert(command.args, arg)
				end
				table.insert(command.args, target_path .. '/' .. output_filename)

				-- Debug and execute
				mp.msg.info("Executing command: " .. table.concat(command.args, " "))
				copyToClipboard(table.concat(command.args, " "))
				mp.command_native_async(command, on_ffmpeg_finish)
			elseif cut_mode == 2 then
				format = "mp4"
				for _, i in ipairs(reencodestock_start) do table.insert(komenda, i) end
				for _, i in ipairs {
					"-map", string.format("0:s:%d", mp.get_property_number("current-tracks/sub/id") - 1), "-y", "-map_chapters", "-1", "-map_metadata", "-1",
					target_path .. "clip_cutter_subtitle.ass" } do table.insert(komenda, i) end
				mp.command_native_async(komenda)
				wait(5)
				subtitle_path = string.gsub(target_path, "\\", "/") .. "clip_cutter_subtitle.ass"
				subtitle_path = string.gsub(subtitle_path, ":", "\\:")
				komenda = {}
				for _, i in ipairs(reencodestock_start) do table.insert(komenda, i) end
				for _, i in ipairs(mapping) do table.insert(komenda, i) end
				for _, i in ipairs {
					"-c:v", "libx264", "-vf", "subtitles=\'" .. subtitle_path .. "\',format=yuv420p", "-ac", "2", "-y",
					string.format(target_path .. "%s_%s_%s.%s", mp.get_property("filename/no-ext"), timestamp_start, timestamp_end, format) } do
					table.insert(komenda, i)
				end
				mp.command_native_async(komenda)
				wait(5)
				os.remove(target_path .. "clip_cutter_subtitle.ass")
			elseif cut_mode == 3 then
				format = "gif"
				for _, i in ipairs(reencodestock_start) do table.insert(komenda, i) end
				for _, i in ipairs { "-vf", "scale=-1:432:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" } do
					table.insert(komenda, i)
				end
				table.insert(komenda, "-y")
				table.insert(komenda,
					string.format(target_path .. "%s_%s_%s.%s", mp.get_property("filename/no-ext"), timestamp_start,
						timestamp_end, format))
				mp.command_native_async(komenda)
			elseif cut_mode == 4 then
				check_for_crop()
				format = "gif"
				for _, i in ipairs(reencodestock_start) do table.insert(komenda, i) end
				for _, i in ipairs { "-vf", string.format("%ssplit[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", filter) } do
					table.insert(komenda, i)
				end
				table.insert(komenda, "-y")
				table.insert(komenda,
					string.format(target_path .. "%s_%s_%s.%s", mp.get_property("filename/no-ext"), timestamp_start,
						timestamp_end, format))
				mp.command_native_async(komenda)
			elseif cut_mode == 5 then
				format = "mp4"
				for _, i in ipairs(copystock_start) do table.insert(komenda, i) end
				for _, i in ipairs(mapping) do table.insert(komenda, i) end
				for _, i in ipairs(copystock_end) do table.insert(komenda, i) end
				table.insert(komenda,
					string.format(target_path .. "%s_%s_%s.%s", mp.get_property("filename/no-ext"), timestamp_start,
						timestamp_end, format))
				mp.command_native_async(komenda)
			else
				mp.osd_message("Unsupported cut mode")
			end
		else
			mp.osd_message("Start time is later than or equal to end time.")
			time_pos_start = nil
			time_pos_end = nil
		end
	else
		mp.osd_message("No starting position selected.")
	end
end

-- Add key bindings for all necessary commands
mp.add_key_binding(nil, "time-start", function() save_time_pos() end)
mp.add_key_binding(nil, "time-end", function() clipCutter() end)
mp.add_key_binding(nil, "mode-swtich", function() mode_switch() end)
mp.add_key_binding(nil, "slicing-mark", function() slicing_mark() end)
