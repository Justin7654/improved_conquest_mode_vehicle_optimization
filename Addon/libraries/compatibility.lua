--[[


	Library Setup


]]

-- required libraries
require("libraries.debugging")
require("libraries.island")
require("libraries.setup")

-- library name
local Compatibility = {}

-- shortened library name
local comp = Compatibility

--[[


	Variables
   

]]

--# stores which versions require compatibility updates
local version_updates = {
	"(0.3.0.78)",
	"(0.3.0.79)"
}

--[[


	Classes


]]

---@class VERSION_DATA
---@field data_version string the version which the data is on currently
---@field version string the version which the mod is on
---@field versions_outdated integer how many versions the data is out of date
---@field is_outdated boolean if the data is outdated compared to the mod
---@field newer_versions table a table of versions which are newer than the current, indexed by index, value as version string

--[[


	Functions         


]]

--# creates version data for the specified version, for use in the version_history table
---@param version string the version you want to create the data on
---@return table version_history_data the data of the version
function Compatibility.createVersionHistoryData(version)

	--[[
		calculate ticks played
	]] 
	local ticks_played = g_savedata.tick_counter

	if g_savedata.info.version_history and #g_savedata.info.version_history > 0 then
		for _, version_data in ipairs(g_savedata.info.version_history) do
			ticks_played = ticks_played - (version_data.ticks_played or 0)
		end
	end

	--[[
		
	]]
	local version_history_data = {
		version = version,
		ticks_played = ticks_played,
		backup_g_savedata = {}
	}

	return version_history_data
end

--# returns g_savedata, a copy of g_savedata which when edited, doesnt actually apply changes to the actual g_savedata, useful for backing up.
function Compatibility.getSavedataCopy()

	--d.print("(comp.getSavedataCopy) getting a g_savedata copy...", true, 0)

	--[[
		credit to Woe (https://canary.discord.com/channels/357480372084408322/905791966904729611/1024355759468839074)

		returns a clone/copy of g_savedata
	]]
	
	local function clone(t)
		local copy = {}
		if type(t) == "table" then
			for key, value in next, t, nil do
				copy[clone(key)] = clone(value)
			end
		else
			copy = t
		end
		return copy
	end

	local copied_g_savedata = clone(g_savedata)
	--d.print("(comp.getSavedataCopy) created a g_savedata copy!", true, 0)

	return copied_g_savedata
end

--# migrates the version system to the new one implemented in 0.3.0.78
---@param overwrite_g_savedata boolean if you want to overwrite g_savedata, usually want to keep false unless you've already got a backup of g_savedata
---@return table migrated_g_savedata
---@return boolean is_success if it successfully migrated the versioning system
function Compatibility.migrateVersionSystem(overwrite_g_savedata)

	d.print("migrating g_savedata...", false, 0)

	--[[
		create a local copy of g_savedata, as changes we make we dont want to be applied to the actual g_savedata
	]]

	local migrated_g_savedata = comp.getSavedataCopy()

	--[[
		make sure that the version_history table doesnt exist
	]]
	if g_savedata.info.version_history then
		-- if it already does, then abort, as the version system is already migrated
		d.print("(comp.migrateVersionSystem) the version system has already been migrated!", true, 1)
		return nil, false
	end

	--[[
		create the version_history table
	]]
	if overwrite_g_savedata then
		g_savedata.info.version_history = {}
	end

	migrated_g_savedata.info.version_history = {}

	--[[
		create the version history data, with the previous version the creation version 
		sadly, we cannot reliably get the last version used for versions 0.3.0.77 and below
		so we have to make this assumption
	]]

	if overwrite_g_savedata then
		table.insert(g_savedata.info.version_history, comp.createVersionHistoryData(migrated_g_savedata.info.creation_version))
	end
	
	table.insert(migrated_g_savedata.info.version_history, comp.createVersionHistoryData(migrated_g_savedata.info.creation_version))

	d.print("migrated g_savedata", false, 0)

	return migrated_g_savedata, true
end

--# returns the version id from the provided version
---@param version string the version you want to get the id of
---@return integer version_id the id of the version
---@return boolean is_success if it found the id of the version
function Compatibility.getVersionID(version)
	--[[
		first, we want to ensure version was provided
		lastly, we want to go through all of the versions stored in the version history, if we find a match, then we return it as the id
		if we cannot find a match, we return nil and false
	]]

	-- ensure version was provided
	if not version then
		d.print("(comp.getVersionID) version was not provided!", false, 1)
		return nil, false
	end

	-- go through all of the versions saved in version_history
	for version_id, version_name in ipairs(g_savedata.info.version_history) do
		if version_name == version then
			return version_id, true
		end
	end

	-- if a version was not found, return nil and false
	return nil, false
end

--# returns the version from the version_id
---@param version_id integer the id of the version
---@return string version the version associated with the id
---@return boolean is_success if it successfully got the version from the id
function Compatibility.getVersion(version_id)

	-- ensure that version_id was specified
	if not version_id then
		d.print("(comp.getVersion) version_id was not provided!", false, 1)
		return nil, false
	end

	-- ensure that it is a number
	if type(version_id) ~= "number" then
		d.print("(comp.getVersion) given version_id was not a number! type: "..type(version_id).." value: "..tostring(version_id), false, 1)
		return nil, false
	end

	local version = g_savedata.info.version_history[version_id] and g_savedata.info.version_history[version_id].version or nil
	return version, version ~= nil
end

--# returns version data about the specified version, or if left blank, the current version
---@param version string the current version, leave blank if want data on current version
---@return VERSION_DATA version_data the data about the version
---@return boolean is_success if it successfully got the version data
function Compatibility.getVersionData(version)

	local version_data = {
		data_version = "",
		is_outdated = false,
		version = "",
		versions_outdated = 0,
		newer_versions = {}
	}

	local copied_g_savedata = comp.getSavedataCopy() -- local copy of g_savedata so any changes we make to it wont affect any backups we may make

	--[[
		first, we want to ensure that the version system is migrated
		second, we want to get the id of the version depending on the given version argument
		third, we want to get the data version
		fourth, we want to count how many versions out of date the data version is from the mod version
		fifth, we want to want to check if the version is outdated
		and lastly, we want to return the data
	]]

	-- (1) check if the version system is not migrated
	if not g_savedata.info.version_history then
		local migrated_g_savedata, is_success = comp.migrateVersionSystem() -- migrate the version data
		if not is_success then
			d.print("(comp.getVersionData) failed to migrate version system. This is probably not good!", false, 1)
			return nil, false
		end

		-- set copied_g_savedata as migrated_g_savedata
		copied_g_savedata = migrated_g_savedata
	end

	-- (2) get version id
	local version_id = version and comp.getVersionID(version) or #copied_g_savedata.info.version_history

	-- (3) get data version
	--d.print("(comp.getVersionData) data_version: "..tostring(copied_g_savedata.info.version_history[version_id].version))
	version_data.data_version = copied_g_savedata.info.version_history[version_id].version

	-- (4) count how many versions out of date the data is
	for _, version_name in ipairs(version_updates) do
		--[[
			first, we want to check if the release version is greater (x.#.#.#)
			if not, second we want to check if the majour version is greater (#.x.#.#)
			if not, third we want to check if the minor version is greater (#.#.x.#)
			if not, lastly we want to check if the commit version is greater (#.#.#.x)
		]]

		-- (4.1) check if release version is outdated (x.#.#.#)
		if (math.tointeger(string.match(version_name, "%((%d+)%.")) or 0) > (math.tointeger(string.match(version_data.data_version, "%((%d+)%.")) or 0) then
			table.insert(version_data.newer_versions, version_name)
			d.print("found new release version: "..version_name.." current version: "..version_data.data_version, false, 0)

		-- (4.2) check if majour version is outdated (#.x.#.#)
		elseif (math.tointeger(string.match(version_name, "%(%d+%.(%d+)")) or 0) > (math.tointeger(string.match(version_data.data_version, "%(%d+%.(%d+)")) or 0) then
			table.insert(version_data.newer_versions, version_name)
			d.print("found new majour version: "..version_name.." current version: "..version_data.data_version, false, 0)

		-- (4.3) check if minor version is outdated (#.#.x.#)
		elseif (math.tointeger(string.match(version_name, "%(%d+%.%d+%.(%d+)")) or 0) > (math.tointeger(string.match(version_data.data_version, "%(%d+%.%d+%.(%d+)")) or 0) then
			table.insert(version_data.newer_versions, version_name)
			d.print("found new minor version: "..version_name.." current version: "..version_data.data_version, false, 0)
		
		-- (4.4) check if commit version is outdated (#.#.#.x)
		elseif (math.tointeger(string.match(version_name, "%(%d+%.%d+%.%d+%.*(%d*)%)")) or 0) > (math.tointeger(string.match(version_data.data_version, "%(%d+%.%d+%.%d+%.*(%d*)%)")) or 0) then
			table.insert(version_data.newer_versions, version_name)
			d.print("found new commit version: "..version_name.." current version: "..version_data.data_version, false, 0)
		end
	end

	-- count how many versions its outdated
	version_data.versions_outdated = #version_data.newer_versions

	-- (5) check if its outdated
	version_data.is_outdated = version_data.versions_outdated > 0

	return version_data, true
end

--# saves backup of current g_savedata
---@return boolean is_success if it successfully saved a backup of the savedata
function Compatibility.saveBackup()
	--[[
		first, we want to save a current local copy of the g_savedata
		second we want to ensure that the g_savedata.info.version_history table is created
		lastly, we want to save the backup g_savedata
	]]

	-- create local copy of g_savedata
	local backup_g_savedata = comp.getSavedataCopy()

	if not g_savedata.info.version_history then -- if its not created (pre 0.3.0.78)
		d.print("(comp.saveBackup) migrating version system", true, 0)
		local migrated_g_savedata, is_success = comp.migrateVersionSystem(true) -- migrate version system
		if not is_success then
			d.print("(comp.saveBackup) failed to migrate version system. This is probably not good!", false, 1)
			return false
		end

		if not g_savedata.info.version_history then
			d.print("(comp.saveBackup) successfully migrated version system, yet g_savedata doesn't contain the new version system, this is not good!", false, 1)
		end
	end

	local version_data, is_success = comp.getVersionData()
	if version_data.data_version ~= g_savedata.info.version_history[#g_savedata.info.version_history].version then
		--d.print("version_data.data_version: "..tostring(version_data.data_version).."\ng_savedata.info.version_history[#g_savedata.info.version.version_history].version: "..tostring(g_savedata.info.version_history[#g_savedata.info.version_history].version))
		g_savedata.info.version_history[#g_savedata.info.version_history + 1] = comp.createVersionHistoryData()
	end

	-- save backup g_savedata
	g_savedata.info.version_history[#g_savedata.info.version_history].backup_g_savedata = backup_g_savedata

	-- remove g_savedata backups which are from over 2 data updates ago
	local backup_versions = {}
	for version_index, version_history_data in ipairs(g_savedata.info.version_history) do
		if version_history_data.backup_g_savedata.info then
			table.insert(backup_versions, version_index)
		end
	end
	
	if #backup_versions >= 3 then
		d.print("Deleting old backup data...", false, 0)
		for backup_index, backup_version_index in ipairs(backup_versions) do
			d.print("Deleting backup data for "..g_savedata.info.version_history[backup_version_index].version, false, 0)
			backup_versions[backup_index] = nil
			g_savedata.info.version_history[backup_version_index].backup_g_savedata = {}

			if #backup_versions <= 2 then
				d.print("Deleted old backup data.", false, 0)
				break
			end
		end
	end

	return true
end

--# updates g_savedata to be compatible with the mod version, to ensure that worlds are backwards compatible.
function Compatibility.update()

	-- ensure that we're actually outdated before proceeding
	local version_data, is_success = comp.getVersionData()
	if not is_success then
		d.print("(comp.update) failed to get version data! this is probably bad!", false, 1)
		return
	end

	if not version_data.is_outdated then
		d.print("(comp.update) according to version data, the data is not outdated. This is probably not good!", false, 1)
		return
	end

	d.print("ICM's data is "..version_data.versions_outdated.." version"..(version_data.versions_outdated > 1 and "s" or "").." out of date!", false, 0)

	-- save backup
	local backup_saved = comp.saveBackup()
	if not backup_saved then
		d.print("(comp.update) Failed to save backup. This is probably not good!", false, 1)
		return false
	end

	d.print("Creating new version history for "..version_data.newer_versions[1].."...", false, 0)
	local version_history_data = comp.createVersionHistoryData(version_data.newer_versions[1])
	g_savedata.info.version_history[#g_savedata.info.version_history+1] = version_history_data
	d.print("Successfully created new version history for "..version_data.newer_versions[1]..".", false, 0)

	-- check for 0.3.0.78 changes
	if version_data.newer_versions[1] == "(0.3.0.78)" then
		d.print("Successfully updated ICM data to "..version_data.newer_versions[1]..", Cleaning up old data...", false, 0)

		-- clean up old data
		g_savedata.info.creation_version = nil
		g_savedata.info.full_reload_versions = nil
		g_savedata.info.awaiting_reload = nil

		-- clean up old player_data
		for steam_id, player_data in pairs(g_savedata.player_data) do
			player_data.timers = nil
			player_data.fully_reloading = nil
			player_data.do_as_i_say = nil
		end		
	elseif version_data.newer_versions[1] == "(0.3.0.79)" then -- 0.3.0.79 changes

		-- update the island data with the proper zones, as previously, the zone system improperly filtered out NSO compatible and incompatible zones
		local spawn_zones = sup.spawnZones()
		local tile_zones = sup.sortSpawnZones(spawn_zones)

		for tile_name, zones in pairs(tile_zones) do
			local island, is_success = Island.getDataFromName(tile_name)
			island.zones = zones
		end

		if g_savedata.info.version_history[1].ticked_played then
			g_savedata.info.version_history.ticks_played = g_savedata.info.version_history.ticked_played
			g_savedata.info.version_history.ticked_played = nil
		end

		d.print("Successfully updated ICM data to "..version_data.newer_versions[1], false, 0)
	end

	d.print("ICM data is now up to date with "..version_data.newer_versions[1]..".", false, 0)

	just_migrated = true
end

--# prints outdated message and starts update
function Compatibility.outdated()
	-- print that its outdated
	d.print("ICM data is outdated! attempting to automatically update...", false, 0)

	-- start update process
	comp.update()
end

--# verifies that the mod is currently up to date
function Compatibility.verify()
	d.print("verifying if ICM data is up to date...", false, 0)
	--[[
		first, check if the versioning system is up to date
	]]
	if not g_savedata.info.version_history then
		-- the versioning system is not up to date
		comp.outdated()
	else
		-- check if we're outdated
		local version_data, is_success = comp.getVersionData()

		if not is_success then
			d.print("(comp.verify) failed to get version data! this is probably bad!", false, 1)
			return
		end

		-- if we're outdated
		if version_data.is_outdated then
			comp.outdated()
		end
	end
end

--# shows the message to save the game and then load the save to complete migration
function Compatibility.showSaveMessage()
	is_dlc_weapons = false
	d.print("ICM Data has been migrated, to complete the process, please save the world, and then load the saved world. ICM has been disabled until this is done.", false, 0)
	s.setPopupScreen(-1, s.getMapID(), "ICM Migration", true, "Please save world and then load save to complete data migration process. ICM has been disabled till this is complete.", 0, 0)
end
