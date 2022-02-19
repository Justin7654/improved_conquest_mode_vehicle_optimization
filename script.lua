local spawnModifiers = {}

local s = server
local m = matrix
local sm = spawnModifiers

local IMPROVED_CONQUEST_VERSION = "(0.2.0.44)"

local MAX_SQUAD_SIZE = 3
local MIN_ATTACKING_SQUADS = 2
local MAX_ATTACKING_SQUADS = 3

local COMMAND_NONE = "nocomm"
local COMMAND_ATTACK = "attack"
local COMMAND_DEFEND = "defend"
local COMMAND_INVESTIGATE = "investigate"
local COMMAND_ENGAGE = "engage"
local COMMAND_PATROL = "patrol"
local COMMAND_STAGE = "stage"
local COMMAND_RESUPPLY = "resupply"
local COMMAND_TURRET = "turret"
local COMMAND_RETREAT = "retreat"
local COMMAND_SCOUT = "scout"

local AI_TYPE_BOAT = "boat"
local AI_TYPE_LAND = "land"
local AI_TYPE_PLANE = "plane"
local AI_TYPE_HELI = "heli"
local AI_TYPE_TURRET = "turret"

local VEHICLE_STATE_PATHING = "pathing"
local VEHICLE_STATE_HOLDING = "holding"

local TARGET_VISIBILITY_VISIBLE = "visible"
local TARGET_VISIBILITY_INVESTIGATE = "investigate"

local REWARD = "reward"
local PUNISH = "punish"

local AI_SPEED_PSEUDO_PLANE = 60
local AI_SPEED_PSEUDO_HELI = 40
local AI_SPEED_PSEUDO_BOAT = 10
local AI_SPEED_PSEUDO_LAND = 5

local RESUPPLY_SQUAD_INDEX = 1

local FACTION_NEUTRAL = "neutral"
local FACTION_AI = "ai"
local FACTION_PLAYER = "player"

local CAPTURE_RADIUS = 1500
local RESUPPLY_RADIUS = 200
local ISLAND_CAPTURE_AMOUNT_PER_SECOND = 1

local VISIBLE_DISTANCE = 1500
local WAYPOINT_CONSUME_DISTANCE = 100

-- plane ai tuning settings
local PLANE_STRAFE_LOCK_DISTANCE = 800

local PLANE_EXPLOSION_DEPTH = -4
local HELI_EXPLOSION_DEPTH = -4
local BOAT_EXPLOSION_DEPTH = -17

local DEFAULT_SPAWNING_DISTANCE = 10 -- the fallback option for how far a vehicle must be away from another in order to not collide, highly reccomended to set tag

local CRUISE_HEIGHT = 300
local built_locations = {}
local flag_prefab = nil
local is_dlc_weapons = false
local render_debug = false
local g_debug_speed_multiplier = 1

local debug_mode_blinker = false -- blinks between showing the vehicle type icon and the vehicle command icon on the map

local vehicles_debugging = {}

local time = { -- the time unit in ticks, irl time, not in game
	second = 60,
	minute = 3600,
	hour = 216000,
	day = 5184000
}

local default_mods = {
	attack = 0,
	general = 1,
	defend = 0,
	roaming = 0.1,
	stealth = 0.05
}

local ai_training = {
	punishments = {
		-0.02,
		-0.05,
		-0.1,
		-0.15,
		-0.5
	},
	rewards = {
		0.01,
		0.05,
		0.15,
		0.4,
		1
	}
}

local scout_requirement = time.minute*40

local playerData = {
	isDebugging = {},
	isDoAsISay = {}
}

if render_debug then
	local adminID = 0
	playerData.isDebugging.adminID = true
end

local capture_speeds = {
	1,
	1.5,
	1.75
}

local g_holding_pattern = {
    {x=500, z=500},
    {x=500, z=-500},
    {x=-500, z=-500},
    {x=-500, z=500}
}

local g_patrol_route = {
	{ x=0, z=8000 },
	{ x=8000, z=0 },
	{ x=-0, z=-8000 },
	{ x=-8000, z=0 },
	{ x=0, z=8000}
}

local g_is_air_ready = true
local g_is_boats_ready = false
local g_count_squads = 0
local g_count_attack = 0
local g_count_patrol = 0
local g_tick_counter = 0

local g_debug_vehicle_id = "0"

g_savedata = {
	ai_base_island = nil,
	player_base_island = nil,
	controllable_islands = {},
    ai_army = { squadrons = { [RESUPPLY_SQUAD_INDEX] = { command = COMMAND_RESUPPLY, ai_type = "", role = "", vehicles = {}, target_island = nil }} },
	player_vehicles = {},
	debug_data = {},
	constructable_vehicles = {},
	constructable_turrets = {},
	vehicle_list = {},
	terrain_scanner_prefab = {},
	terrain_scanner_links = {},
	is_attack = false,
	info = {
		creation_version = nil,
		full_reload_versions = {},
		has_default_addon = false,
	},
	land_spawn_zones = {},
	tick_counter = 0,
	ai_history = {
		has_defended = 0, -- logs the time in ticks the player attacked at
		defended_charge = 0, -- the charge for it to detect the player is attacking, kinda like a capacitor
	},
	ai_knowledge = {
		last_seen_positions = {}, -- saves the last spot it saw each player, and at which time (tick counter)
		scout = {}, -- the scout progress of each island
	},
}

--[[
        Functions
--]]

function wpDLCDebug(message, requiresDebugging, isError, toPlayer)
	local deb_err = s.getAddonData((s.getAddonIndex())).name..(isError and " Error:" or " Debug:")
	
	if type(message) == "table" then
		printTable(message, requiresDebugging, isError, toPlayer)
	elseif requiresDebugging == true then
		if toPlayer ~= -1 and toPlayer ~= nil then
			if playerData.isDebugging.toPlayer then
				s.announce(deb_err, message, toPlayer)
			end
		else
			for k, v in pairs(playerData.isDebugging) do
				if playerData.isDebugging[k] then
					s.announce(deb_err, message, k)
				end
			end
		end
	else
		s.announce(deb_err, message, toPlayer or "-1")
	end
end

function wpDLCDebugVehicle(id, message, requiresDebugging, isError, toPlayer)
	if vehicles_debugging[id] then
		wpDLCDebug(message, requiresDebugging, isError, toPlayer)
	end
end

function onCreate(is_world_create, do_as_i_say, peer_id)
	if not g_savedata.settings then
		g_savedata.settings = {
			SINKING_MODE = not property.checkbox("Disable Sinking Mode (Sinking Mode disables sea and air vehicle health)", false),
			CONTESTED_MODE = not property.checkbox("Disable Point Contesting", false),
			AI_INITIAL_ISLAND_AMOUNT = property.slider("Starting Amount of AI Bases (not including main bases)", 0, 17, 1, 1),
			AI_PRODUCTION_TIME_BASE = property.slider("AI Production Time (Mins)", 1, 20, 1, 10) * 60 * 60,
			ISLAND_COUNT = property.slider("Island Count - Total AI Max will be 3x this value", 7, 19, 1, 19),
			MAX_PLANE_SIZE = property.slider("AI Planes Max", 0, 8, 1, 2),
			MAX_HELI_SIZE = property.slider("AI Helis Max", 0, 8, 1, 5),
			AI_INITIAL_SPAWN_COUNT = property.slider("AI Initial Spawn Count (* by the amount of initial ai islands)", 0, 15, 1, 10),
			CAPTURE_TIME = property.slider("Capture Time (Mins)", 10, 600, 1, 60) * 60,
			ENEMY_HP = property.slider("AI HP Base - Medium and Large AI will have 2x and 4x this. then 8x if in sinking mode", 0, 2500, 5, 325),
		}
	end

    is_dlc_weapons = s.dlcWeapons()

	local addon_index, is_success = server.getAddonIndex("DLC Weapons AI")
	if is_success then
		g_savedata.info.has_default_addon = true
	end

    if is_dlc_weapons then

		s.announce("Loading Script: " .. s.getAddonData((s.getAddonIndex())).name, "Complete, Version: "..IMPROVED_CONQUEST_VERSION, 0)

        if is_world_create then

			-- allows the player to make the scripts reload as if the world was just created
			-- this command is very dangerous
			if do_as_i_say then
				if peer_id then
					wpDLCDebug(s.getPlayerName(peer_id).." has reloaded the improved conquest mode addon, this command is very dangerous and can break many things", false, false)
					-- removes all ai vehicles
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							killVehicle(squad_index, vehicle_id, true, true)
						end
					end
					-- resets some island data
					for island_index, island in pairs(g_savedata.controllable_islands) do
						-- resets map icons
						updatePeerIslandMapData(-1, island, true)

						-- removes all flags/capture point vehicles
						s.despawnVehicle(island.flag_vehicle.id, true)
					end
					-- reset savedata
					playerData = {
						isDebugging = {},
						isDoAsISay = {}
					}
					g_savedata.land_spawn_zones = {}
					g_savedata.ai_army.squadrons = {}
					g_savedata.ai_base_island.zones = {}
					g_savedata.player_base_island = nil
					g_savedata.ai_base_island = nil
					g_savedata.controllable_islands = {}
					g_savedata.constructable_vehicles = {}
					g_savedata.constructable_turrets = {}
					g_savedata.is_attack = {}
					g_savedata.vehicle_list = {}
					g_savedata.ai_history = {}
					g_savedata.tick_counter = 0
					wpDLCDebug("to complete this process, do ?reload_scripts", false, false, peer_id)

					-- save that this happened, as to aid in debugging errors
					table.insert(g_savedata.info.full_reload_versions, IMPROVED_CONQUEST_VERSION.." (by \""..s.getPlayerName(peer_id).."\")")
				end
			else
				if not peer_id then
					-- things that should never be changed even after this command
					-- such as changing what version the world was created in, as this could lead to issues when trying to debug
					if not g_savedata.info.creation_version then
						g_savedata.info.creation_version = IMPROVED_CONQUEST_VERSION
					end
				end
			end

			turret_zones = s.getZones("turret")

			for land_spawn_index, land_spawn in pairs(s.getZones("land_spawn")) do
				table.insert(g_savedata.land_spawn_zones, land_spawn.transform)
			end

            for i in iterPlaylists() do
                for j in iterLocations(i) do
                    build_locations(i, j)
                end
            end

            for i = 1, #built_locations do
				buildPrefabs(i)
            end

			sm.create()

			local start_island = s.getStartIsland()

			-- init player base
			local flag_zones = s.getZones("capture")
			for flagZone_index, flagZone in pairs(flag_zones) do

				local flag_tile = s.getTile(flagZone.transform)
				if flag_tile.name == start_island.name or (flag_tile.name == "data/tiles/island_43_multiplayer_base.xml" and g_savedata.player_base_island == nil) then
					g_savedata.player_base_island = {
						name = flagZone.name,
						transform = flagZone.transform,
						tags = flagZone.tags,
						faction = FACTION_PLAYER, 
						faction_prev = FACTION_PLAYER,
						is_contested = false,
						capture_timer = g_savedata.settings.CAPTURE_TIME, 
						capture_timer_prev = g_savedata.settings.CAPTURE_TIME,
						map_id = s.getMapID(),
						assigned_squad_index = -1,
						ai_capturing = 0,
						players_capturing = 0,
						defenders = 0,
						is_scouting = false
					}
					flag_zones[flagZone_index] = nil
				end
			end

			-- calculate furthest flag from player
			local furthest_flagZone_index = nil
			local distance_to_player_max = 0
			for flagZone_index, flagZone in pairs(flag_zones) do
				local distance_to_player = m.distance(flagZone.transform, g_savedata.player_base_island.transform)
				if distance_to_player_max < distance_to_player then
					distance_to_player_max = distance_to_player
					furthest_flagZone_index = flagZone_index
				end
			end

			-- set up ai base as furthest from player
			local flagZone = flag_zones[furthest_flagZone_index]
			g_savedata.ai_base_island = {
				name = flagZone.name, 
				transform = flagZone.transform,
				tags = flagZone.tags,
				faction = FACTION_AI, 
				faction_prev = FACTION_AI,
				is_contested = false,
				capture_timer = 0,
				capture_timer_prev = 0,
				map_id = s.getMapID(), 
				assigned_squad_index = -1, 
				production_timer = 0,
				zones = {},
				ai_capturing = 0,
				players_capturing = 0,
				defenders = 0,
				is_scouting = false
			}
			for _, turretZone in pairs(turret_zones) do
				if(m.distance(turretZone.transform, flagZone.transform) <= 1000) then
					table.insert(g_savedata.ai_base_island.zones, turretZone)
				end
			end
			flag_zones[furthest_flagZone_index] = nil

			-- set up remaining neutral islands
			for _, flagZone in pairs(flag_zones) do
				local flag = s.spawnAddonComponent(m.multiply(flagZone.transform, m.translation(0, -7.86, 0)), flag_prefab.playlist_index, flag_prefab.location_index, flag_prefab.object_index, 0)
				local new_island = {
					name = flagZone.name, 
					flag_vehicle = flag, 
					transform = flagZone.transform,
					tags = flagZone.tags,
					faction = FACTION_NEUTRAL, 
					faction_prev = FACTION_NEUTRAL,
					is_contested = false,
					capture_timer = g_savedata.settings.CAPTURE_TIME / 2,
					capture_timer_prev = g_savedata.settings.CAPTURE_TIME / 2,
					map_id = s.getMapID(), 
					assigned_squad_index = -1, 
					zones = {},
					ai_capturing = 0,
					players_capturing = 0,
					defenders = 0,
					is_scouting = false
				}

				for _, turretZone in pairs(turret_zones) do
					if(m.distance(turretZone.transform, flagZone.transform) <= 1000) then
						table.insert(new_island.zones, turretZone)
					end
				end

				table.insert(g_savedata.controllable_islands, new_island)

				if(#g_savedata.controllable_islands >= g_savedata.settings.ISLAND_COUNT) then
					break
				end
			end

			-- sets up scouting data
			for island_index, island in pairs(g_savedata.controllable_islands) do
				tabulate(g_savedata.ai_knowledge.scout, island.name)
				g_savedata.ai_knowledge.scout[island.name].scouted = 0
			end

			-- game setup
			for i = 1, g_savedata.settings.AI_INITIAL_ISLAND_AMOUNT do
				if i <= #g_savedata.controllable_islands - 2 then
					local t, a = getObjectiveIsland()
					t.capture_timer = 0 -- capture nearest ally
					t.faction = FACTION_AI
				end
			end
			
			for i = 1, g_savedata.settings.AI_INITIAL_SPAWN_COUNT --[[* math.min(math.max(g_savedata.settings.AI_INITIAL_ISLAND_AMOUNT, 1), #g_savedata.controllable_islands - 1)--]] do
				spawnAIVehicle() -- spawn initial ai
			end
		else
			for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					s.removeMapObject(0,vehicle_object.map_id)
					s.removeMapLine(0,vehicle_object.map_id)
					for i = 1, #vehicle_object.path - 1 do
						local waypoint = vehicle_object.path[i]
						s.removeMapLine(0, waypoint.ui_id)
					end
				end
			end
		end
	end
end

function buildPrefabs(location_index)
    local location = built_locations[location_index]

	-- construct vehicle-character prefab list
	local vehicle_index = #g_savedata.vehicle_list + 1 or 1
	for key, vehicle in pairs(location.objects.vehicles) do

		local prefab_data = {location = location, vehicle = vehicle, survivors = {}, fires = {}}

		for key, char in  pairs(location.objects.survivors) do
			table.insert(prefab_data.survivors, char)
		end

		for key, fire in  pairs(location.objects.fires) do
			table.insert(prefab_data.fires, fire)
		end

		
		if hasTag(vehicle.tags, "type=wep_turret") or #prefab_data.survivors > 0 then
			table.insert(g_savedata.vehicle_list, vehicle_index, prefab_data)
			g_savedata.vehicle_list[vehicle_index].role = getTagValue(vehicle.tags, "role", true) or "general"
			g_savedata.vehicle_list[vehicle_index].vehicle_type = string.gsub(getTagValue(vehicle.tags, "type", true), "wep_", "") or "unknown"
			g_savedata.vehicle_list[vehicle_index].strategy = getTagValue(vehicle.tags, "strategy", true) or "general"
		end

		--
		--
		-- <<<<<<<<<< get vehicles, and put them into a table, sorted by their directive/role and their type, as well as additional info >>>>>>>>>
		--
		--

		if hasTag(vehicle.tags, "type=wep_turret") then
			table.insert(g_savedata.constructable_turrets, prefab_data)
		elseif #prefab_data.survivors > 0 then
			local varient = getTagValue(vehicle.tags, "varient")
			if not varient then
				local role = getTagValue(vehicle.tags, "role", true) or "general"
				local vehicle_type = string.gsub(getTagValue(vehicle.tags, "type", true), "wep_", "") or "unknown"
				local strategy = getTagValue(vehicle.tags, "strategy", true) or "general"
				tabulate(g_savedata.constructable_vehicles, role, vehicle_type, strategy)
				table.insert(g_savedata.constructable_vehicles[role][vehicle_type][strategy], prefab_data)
				g_savedata.constructable_vehicles[role][vehicle_type][strategy][#g_savedata.constructable_vehicles[role][vehicle_type][strategy]].id = vehicle_index
				wpDLCDebug("set id: "..g_savedata.constructable_vehicles[role][vehicle_type][strategy][#g_savedata.constructable_vehicles[role][vehicle_type][strategy]].id.." | # of vehicles: "..#g_savedata.constructable_vehicles[role][vehicle_type][strategy], false, false)
			else
				tabulate(g_savedata.constructable_vehicles, varient)
				table.insert(g_savedata.constructable_vehicles["varient"], prefab_data)
			end
		end
	end
end

function spawnTurret(island)
	local selected_prefab = g_savedata.constructable_turrets[math.random(1, #g_savedata.constructable_turrets)]

	if (#island.zones < 1) then return end

	local spawnbox_index = math.random(1, #island.zones)
	if island.zones[spawnbox_index].is_spawned == true then
		return
	end
	island.zones[spawnbox_index].is_spawned = true
	local spawn_transform = island.zones[spawnbox_index].transform

	-- spawn objects
	local all_addon_components = {}
	local spawned_objects = {
		spawned_vehicle = spawnObject(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.vehicle, 0, nil, all_addon_components),
		survivors = spawnObjects(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.survivors, all_addon_components),
		fires = spawnObjects(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.fires, all_addon_components),
	}

	if spawned_objects.spawned_vehicle ~= nil then
		local vehicle_survivors = {}
		for key, char in  pairs(spawned_objects.survivors) do
			local c = s.getCharacterData(char.id)
			s.setCharacterData(char.id, c.hp, true, true)
			s.setAIState(char.id, 1)
			s.setAITargetVehicle(char.id, -1)
			table.insert(vehicle_survivors, char)
		end

		local home_x, home_y, home_z = m.position(spawn_transform)
		local vehicle_data = {
			id = spawned_objects.spawned_vehicle.id,
			name = selected_prefab.location.data.name,
			survivors = vehicle_survivors,
			path = {
				[1] = {
					x = home_x,
					y = home_y,
					z = home_z
				}
			},
			state = {
				s = "stationary",
				timer = math.fmod(spawned_objects.spawned_vehicle.id, 300),
				is_simulating = false
			},
			map_id = s.getMapID(),
			ai_type = spawned_objects.spawned_vehicle.ai_type,
			role = getTagValue(selected_prefab.vehicle.tags, "role") or "general",
			size = spawned_objects.spawned_vehicle.size,
			holding_index = 1,
			vision = {
				radius = getTagValue(selected_prefab.vehicle.tags, "visibility_range") or VISIBLE_DISTANCE,
				base_radius = getTagValue(selected_prefab.vehicle.tags, "visibility_range") or VISIBLE_DISTANCE,
				is_radar = hasTag(selected_prefab.vehicle.tags, "radar"),
				is_sonar = hasTag(selected_prefab.vehicle.tags, "sonar")
			},
			spawning_transform = {
				distance = getTagValue(selected_prefab.vehicle.tags, "spawning_distance") or DEFAULT_SPAWNING_DISTANCE
			},
			speed = {
				normal = {
					road = getTagValue(selected_prefab.vehicle.tags, "road_speed_normal") or 0,
					bridge = getTagValue(selected_prefab.vehicle.tags, "bridge_speed_normal") or 0,
					offroad = getTagValue(selected_prefab.vehicle.tags, "offroad_speed_normal") or 0
				},
				aggressive = {
					road = getTagValue(selected_prefab.vehicle.tags, "road_speed_aggressive") or 0,
					bridge = getTagValue(selected_prefab.vehicle.tags, "bridge_speed_aggressive") or 0,
					offroad = getTagValue(selected_prefab.vehicle.tags, "offroad_speed_aggressive") or 0
				}
			},
			capabilities = {
				gps_missiles = hasTag(selected_prefab.vehicle.tags, "GPS_MISSILE")
			},
			strategy = getTagValue(selected_prefab.vehicle.tags, "strategy", true) or "general",
			transform = spawn_transform,
			target_player_id = -1,
			target_vehicle_id = -1,
			home_island = island.name,
			current_damage = 0,
			damage_dealt = {},
			fire_id = nil,
			spawnbox_index = spawnbox_index,
		}

		if #spawned_objects.fires > 0 then
			vehicle_data.fire_id = spawned_objects.fires[1].id
		end
		
		local squad = addToSquadron(vehicle_data)
		setSquadCommand(squad, COMMAND_TURRET)

		wpDLCDebug("spawning island turret", true, false)
	end
end

function spawnAIVehicle(requested_prefab)
	local plane_count = 0
	local heli_count = 0
	local army_count = 0
	local land_count = 0
	
	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if vehicle_object.ai_type ~= AI_TYPE_TURRET then army_count = army_count + 1 end
			if vehicle_object.ai_type == AI_TYPE_PLANE then plane_count = plane_count + 1 end
			if vehicle_object.ai_type == AI_TYPE_HELI then heli_count = heli_count + 1 end
			if vehicle_object.ai_type == AI_TYPE_LAND then land_count = land_count + 1 end
		end
	end

	if army_count >= #g_savedata.controllable_islands * MAX_SQUAD_SIZE then return end
	
	local selected_prefab = nil

	if requested_prefab then
		selected_prefab = sm.spawn(true, requested_prefab) 
	else
		selected_prefab = sm.spawn(false)
	end

	local player_list = s.getPlayers()

	local selected_spawn = 0
	local selected_spawn_transform = g_savedata.ai_base_island.transform

	-------
	-- get spawn location
	-------

	-- if the vehicle we want to spawn is an attack vehicle, we want to spawn it as close to their objective as possible
	if getTagValue(selected_prefab.vehicle.tags, "role") == "attack" or getTagValue(selected_prefab.vehicle.tags, "role") == "scout" then
		target, ally = getObjectiveIsland()
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if island.faction == FACTION_AI then
				if selected_spawn_transform == nil or xzDistance(target.transform, island.transform) < xzDistance(target.transform, selected_spawn_transform) then
					if playersNotNearby(player_list, island.transform, 3000, true) then -- makes sure no player is within 3km
						if hasTag(island.tags, "can_spawn="..string.gsub(getTagValue(selected_prefab.vehicle.tags, "type", true), "wep_", "")) or hasTag(selected_prefab.vehicle.tags, "role=scout") then -- if it can spawn at the island
							selected_spawn_transform = island.transform
							selected_spawn = island_index
						end
					end
				end
			end
		end
	-- (A) if the vehicle we want to spawn is a defensive vehicle, we want to spawn it on the island that has the least amount of defence
	-- (B) if theres multiple, pick the island we saw the player closest to
	-- (C) if none, then spawn it at the island which is closest to the player's island
	elseif getTagValue(selected_prefab.vehicle.tags, "role") == "defend" then
		local lowest_defenders = nil
		local check_last_seen = false
		local islands_needing_checked = {}
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if island.faction == FACTION_AI then
				if playersNotNearby(player_list, island.transform, 3000, true) then -- make sure no players are within 3km of the island
					if hasTag(island.tags, "can_spawn="..string.gsub(getTagValue(selected_prefab.vehicle.tags, "type", true), "wep_", "")) or hasTag(selected_prefab.vehicle.tags, "role=scout") then -- if it can spawn at the island
						if not lowest_defenders or island.defenders < lowest_defenders then -- choose the island with the least amount of defence (A)
							lowest_defenders = island.defenders -- set the new lowest defender amount on an island
							selected_spawn_transform = island.transform
							selected_spawn = island_index
							check_last_seen = false -- say that we dont need to do a tie breaker
							islands_needing_checked = {}
						elseif lowest_defenders == island.defenders then -- if two islands have the same amount of defenders
							islands_needing_checked[selected_spawn] = selected_spawn_transform
							islands_needing_checked[island_index] = island.transform
							check_last_seen = true -- we need a tie breaker
						end
					end
				end
			end
		end
		if check_last_seen then -- do a tie breaker (B)
			local closest_player_pos = nil
			for player_steam_id, player_transform in pairs(g_savedata.ai_knowledge.last_seen_positions) do
				for island_index, island_transform in pairs(islands_needing_checked) do
					local player_to_island_dist = xzDistance(player_transform, island_transform)
					if player_to_island_dist < 6000 then
						if not closest_player_pos or player_to_island_dist < closest_player_pos then
							if playersNotNearby(player_list, island_transform, 3000, true) then
								if hasTag(g_savedata.controllable_islands[island_index].tags, "can_spawn="..string.gsub(getTagValue(selected_prefab.vehicle.tags, "type", true), "wep_", "")) or hasTag(selected_prefab.vehicle.tags, "role=scout") then -- if it can spawn at the island
									closest_player_pos = player_transform
									selected_spawn_transform = island_transform
									selected_spawn = island_index
								end
							end
						end
					end
				end
			end
			if not closest_player_pos then -- if no players were seen this game, spawn closest to the closest player island (C)
				for island_index, island_transform in pairs(islands_needing_checked) do
					for player_island_index, player_island in pairs(g_savedata.controllable_islands) do
						if player_island.faction == FACTION_PLAYER then
							if xzDistance(selected_spawn_transform, island_transform) > xzDistance(player_island.transform, island_transform) then
								if playersNotNearby(player_list, island_transform, 3000, true) then
									if hasTag(g_savedata.controllable_islands[island_index].tags, "can_spawn="..string.gsub(getTagValue(selected_prefab.vehicle.tags, "type", true), "wep_", "")) or hasTag(selected_prefab.vehicle.tags, "role=scout") then -- if it can spawn at the island
										selected_spawn_transform = island_transform
										selected_spawn = island_index
									end
								end
							end
						end
					end
				end
			end
		end
	-- spawn it at a random ai island
	else
		local valid_islands = {}
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if island.faction == FACTION_AI then
				if playersNotNearby(player_list, island.transform, 3000, true) then
					if hasTag(island.tags, "can_spawn="..string.gsub(getTagValue(selected_prefab.vehicle.tags, "type", true), "wep_", "")) or hasTag(selected_prefab.vehicle.tags, "role=scout") then
						table.insert(valid_islands, island)
					end
				end
			end
		end
		if #valid_islands > 0 then
			random_island = math.random(1, #valid_islands)
			selected_spawn_transform = valid_islands[random_island].transform
			selected_spawn = random_island
		end
	end

	local spawn_transform = selected_spawn_transform
	if hasTag(selected_prefab.vehicle.tags, "type=wep_boat") then
		local boat_spawn_transform, found_ocean = s.getOceanTransform(spawn_transform, 500, 2000)
		if found_ocean == false then wpDLCDebug("unable to find ocean to spawn boat!", true, false); return end
		spawn_transform = m.multiply(boat_spawn_transform, m.translation(math.random(-500, 500), 0, math.random(-500, 500)))
	elseif hasTag(selected_prefab.vehicle.tags, "type=wep_land") then
		local land_spawn_locations = {}
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if island.faction == FACTION_AI then
				if g_savedata.land_spawn_zones then
					for land_spawn_index, land_spawn in pairs(g_savedata.land_spawn_zones) do
						if m.distance(land_spawn, island.transform) <= 1000 or m.distance(land_spawn, g_savedata.ai_base_island.transform) <= 1000 then
							table.insert(land_spawn_locations, land_spawn)
						end
					end
				else
					for land_spawn_index, land_spawn in pairs(s.getZones("land_spawn")) do
						table.insert(g_savedata.land_spawn_zones, land_spawn.transform)
					end
				end
			end
		end
		if #land_spawn_locations > 0 then
			spawn_transform = land_spawn_locations[math.random(1, #land_spawn_locations)]
		else
			wpDLCDebug("No suitible spawn location found for land vehicle, attempting to spawn a different vehicle", true, false)
			spawnAIVehicle()
			return false
		end
	else
		if
			hasTag(selected_prefab.vehicle.tags, "type=wep_heli") and heli_count <= g_savedata.settings.MAX_HELI_SIZE 
			or hasTag(selected_prefab.vehicle.tags, "type=wep_plane") and plane_count <= g_savedata.settings.MAX_PLANE_SIZE 
			or hasTag(selected_prefab.vehicle.tags, "type=wep_plane") and requested_prefab 
			or hasTag(selected_prefab.vehicle.tags, "type=wep_heli") and requested_prefab 
			then

			spawn_transform = m.multiply(selected_spawn_transform, m.translation(math.random(-500, 500), CRUISE_HEIGHT + 200, math.random(-500, 500)))
		else
			wpDLCDebug("unable to spawn vehicle, attempting to spawn another vehicle...", true, false)
			spawnAIVehicle()
			return false
		end
	end

	-- check to make sure no vehicles are too close, as this could result in them spawning inside each other
	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if m.distance(spawn_transform, vehicle_object.transform) < (getTagValue(selected_prefab.vehicle.tags, "spawning_distance") or DEFAULT_SPAWNING_DISTANCE + vehicle_object.spawning_transform.distance) then
				wpDLCDebug("cancelling spawning vehicle, due to its proximity to vehicle "..vehicle_id, true, true)
				return false
			end
		end
	end

	-- spawn objects
	local all_addon_components = {}
	local spawned_objects = {
		spawned_vehicle = spawnObject(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.vehicle, 0, nil, all_addon_components),
		survivors = spawnObjects(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.survivors, all_addon_components),
		fires = spawnObjects(spawn_transform, selected_prefab.location.playlist_index, selected_prefab.location.location_index, selected_prefab.fires, all_addon_components),
	}
	local vehX, vehY, vehZ = m.position(spawn_transform)
	if selected_prefab.vehicle.display_name ~= nil then
		wpDLCDebug("spawned vehicle: "..selected_prefab.vehicle.display_name.." at X: "..vehX.." Y: "..vehY.." Z: "..vehZ, true, false)
	else
		wpDLCDebug("the selected vehicle is nil", true, true)
	end

	wpDLCDebug("spawning army vehicle: "..selected_prefab.location.data.name.." / "..selected_prefab.location.playlist_index.." / "..selected_prefab.vehicle.display_name, true, false)

	if spawned_objects.spawned_vehicle ~= nil then
		local vehicle_survivors = {}
		for key, char in  pairs(spawned_objects.survivors) do
			local c = s.getCharacterData(char.id)
			s.setCharacterData(char.id, c.hp, true, true)
			s.setAIState(char.id, 1)
			s.setAITargetVehicle(char.id, -1)
			table.insert(vehicle_survivors, char)
		end

		local home_x, home_y, home_z = m.position(spawn_transform)

		local vehicle_data = { 
			id = spawned_objects.spawned_vehicle.id,
			name = selected_prefab.location.data.name,
			survivors = vehicle_survivors, 
			path = { 
				[1] = {
					x = home_x, 
					y = CRUISE_HEIGHT + (spawned_objects.spawned_vehicle.id % 10 * 20), 
					z = home_z
				} 
			}, 
			state = { 
				s = VEHICLE_STATE_HOLDING, 
				timer = math.fmod(spawned_objects.spawned_vehicle.id, 300),
				is_simulating = false
			}, 
			map_id = s.getMapID(), 
			ai_type = spawned_objects.spawned_vehicle.ai_type,
			role = getTagValue(selected_prefab.vehicle.tags, "role", true) or "general",
			size = spawned_objects.spawned_vehicle.size,
			holding_index = 1, 
			vision = { 
				radius = getTagValue(selected_prefab.vehicle.tags, "visibility_range") or VISIBLE_DISTANCE,
				base_radius = getTagValue(selected_prefab.vehicle.tags, "visibility_range") or VISIBLE_DISTANCE,
				is_radar = hasTag(selected_prefab.vehicle.tags, "radar"),
				is_sonar = hasTag(selected_prefab.vehicle.tags, "sonar")
			},
			spawning_transform = {
				distance = getTagValue(selected_prefab.vehicle.tags, "spawning_distance") or DEFAULT_SPAWNING_DISTANCE
			},
			speed = {
				normal = {
					road = getTagValue(selected_prefab.vehicle.tags, "road_speed_normal"),
					bridge = getTagValue(selected_prefab.vehicle.tags, "bridge_speed_normal"),
					offroad = getTagValue(selected_prefab.vehicle.tags, "offroad_speed_normal")
				},
				aggressive = {
					road = getTagValue(selected_prefab.vehicle.tags, "road_speed_aggressive"),
					bridge = getTagValue(selected_prefab.vehicle.tags, "bridge_speed_aggressive"),
					offroad = getTagValue(selected_prefab.vehicle.tags, "offroad_speed_aggressive")
				}
			},
			capabilities = {
				gps_missiles = hasTag(selected_prefab.vehicle.tags, "GPS_MISSILE")
			},
			strategy = getTagValue(selected_prefab.vehicle.tags, "strategy", true) or "general",
			is_resupply_on_load = false,
			transform = spawn_transform,
			target_vehicle_id = -1,
			target_player_id = -1,
			current_damage = 0,
			damage_dealt = {},
			fire_id = nil,
		}

		if #spawned_objects.fires > 0 then
			vehicle_data.fire_id = spawned_objects.fires[1].id
		end

		local squad = addToSquadron(vehicle_data)
		if getTagValue(selected_prefab.vehicle.tags, "role", true) == "scout" then
			setSquadCommand(squad, COMMAND_SCOUT)
		elseif getTagValue(selected_prefab.vehicle.tags, "role", true) == "turret" then
			setSquadCommand(squad, COMMAND_TURRET)
		end
		return true
	end
	return false
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, arg1, arg2, arg3, arg4)
	if is_dlc_weapons then
		if string.sub(command, 1, 5) == "?WDLC" or string.sub(command, 1, 5) == "?wep_" or command == "?target" or string.sub(command, 1, 11) == "?WeaponsDLC" then
			-- non admin commands

			-- admin commands
			if is_admin then
				if command == "?wep_reset" then
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						if squad_index ~= RESUPPLY_SQUAD_INDEX then
							setSquadCommand(squad, COMMAND_NONE)
						end
					end
					g_is_air_ready = true
					g_is_boats_ready = false
					g_savedata.is_attack = false

				elseif command == "?wep_debug_vehicle" then
					g_debug_vehicle_id = arg1

				elseif command == "?wep_debug_speed" then
						g_debug_speed_multiplier = arg1

				elseif command == "?wep_vreset" then
						s.resetVehicleState(arg1)

				elseif command == "?target" then
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							for i, char in  pairs(vehicle_object.survivors) do
								s.setAITargetVehicle(char.id, arg1)
							end
						end
					end

				elseif command == "?WeaponsDLCSpawnVehicle" or command == "?WDLCSV" then
					if arg1 then
						vehicle_id = sm.getVehicleListID(string.gsub(arg1, "_", " "))
						if vehicle_id or arg1 == "scout" then
							valid_vehicle = true
							wpDLCDebug("Spawning \""..arg1.."\"", false, false, user_peer_id)
							if arg1 ~= "scout" then
								spawnAIVehicle(vehicle_id)
							else
								spawnAIVehicle(arg1)
							end
						else
							wpDLCDebug("Was unable to find a vehicle with the name \""..arg1.."\", use ?WDLCVL to see all valid vehicle names | this is case sensitive, and all spaces must be replaced with underscores")
						end
					else -- if vehicle not specified, spawn random vehicle
						wpDLCDebug("Spawning Random Enemy AI Vehicle", false, false, user_peer_id)
						spawnAIVehicle()
					end

				elseif command == "?WeaponsDLCVehicleList" or command == "?WDLCVL" then
					wpDLCDebug("Valid Vehicles:", false, false, user_peer_id)
					for vehicle_index, vehicle_object in pairs(g_savedata.vehicle_list) do
						wpDLCDebug("raw name: \""..vehicle_object.location.data.name.."\"", false, false, user_peer_id)
						wpDLCDebug("formatted name (for use in commands): \""..string.gsub(vehicle_object.location.data.name, " ", "_").."\"", false, false, user_peer_id)
					end

				elseif command == "?WeaponsDLCDebug" or command == "?WDLCD" then
					if arg1 then
						vehicles_debugging[tonumber(arg1)] = not vehicles_debugging[tonumber(arg1)]
						local enDis = "dis"
						if vehicles_debugging[tonumber(arg1)] then
							enDis = "en"
						end
						wpDLCDebug(enDis.."abled debugging for vehicle id: "..arg1, false, false, user_peer_id)
					else
						playerData.isDebugging.user_peer_id = not playerData.isDebugging.user_peer_id

						if playerData.isDebugging.user_peer_id ~= true then
							wpDLCDebug("Debugging Disabled", false, false, user_peer_id)
						else
							wpDLCDebug("Debugging Enabled", false, false, user_peer_id)
						end
						
						local keep_render_debug = false
						for k, v in pairs(playerData.isDebugging) do
							if playerData.isDebugging[k] then
								render_debug = true
								keep_render_debug = true
							end
						end

						if not keep_render_debug then
							render_debug = false
						end

						for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
							for vehicle_id, vehicle_object in pairs(squad.vehicles) do
								s.removeMapObject(user_peer_id,vehicle_object.map_id)
								s.removeMapLine(user_peer_id,vehicle_object.map_id)
								for i = 1, #vehicle_object.path - 1 do
									local waypoint = vehicle_object.path[i]
									s.removeMapLine(user_peer_id, waypoint.ui_id)
								end
							end
						end
					end
				elseif command == "?WDLCST" or command == "?WeaponsDLCSpawnTurret" then
					local turrets_spawned = 1
					spawnTurret(g_savedata.ai_base_island)
					for island_index, island in pairs(g_savedata.controllable_islands) do
						if island.faction == FACTION_AI then
							spawnTurret(island)
							turrets_spawned = turrets_spawned + 1
						end
					end
					wpDLCDebug("attempted to spawn "..turrets_spawned.." turrets", false, false, user_peer_id)
				elseif command == "?WDLCCP" or command == "?WeaponsDLCCapturePoint" then
					if arg1 and arg2 then
						local is_island = false
						for island_index, island in pairs(g_savedata.controllable_islands) do
							if island.name == string.gsub(arg1, "_", " ") then
								is_island = true
								if island.faction ~= arg2 then
									if arg2 == FACTION_AI or arg2 == FACTION_NEUTRAL or arg2 == FACTION_PLAYER then
										captureIsland(island, arg2, user_peer_id)
									else
										wpDLCDebug(arg2.." is not a valid faction! valid factions: | ai | neutral | player", false, true, user_peer_id)
									end
								else
									wpDLCDebug(island.name.." is already set to "..island.faction..".", false, true, user_peer_id)
								end
							end
						end
						if not is_island then
							wpDLCDebug(arg1.." is not a valid island! note: required to use \"_\" instead of \" \" in its name", false, true, user_peer_id)
						end
					else
						wpDLCDebug("Invalid Syntax! command usage: ?WDLCCP (island_name) (faction)", false, true, user_peer_id)
					end

				elseif command == "?WDLC_RELOAD_ADDON" or command == "?WeaponsDLC_RELOAD_ADDON" then
					if playerData.isDoAsISay.user_peer_id == true and arg1 == "do_as_i_say" then
						wpDLCDebug(s.getPlayerName(user_peer_id).." IS FULLY RELOADING IMPROVED CONQUEST MODE ADDON, THINGS HAVE A HIGH CHANCE OF BREAKING!", false, false)
						onCreate(true, true, user_peer_id)
					elseif playerData.isDoAsISay.user_peer_id == true and not arg1 then
						wpDLCDebug("action has been reverted, no longer will be reloading addon", false, false, user_peer_id)
						playerData.isDoAsISay.user_peer_id = not playerData.isDoAsISay.user_peer_id
					elseif not arg1 then
						wpDLCDebug("WARNING: This command can break your entire world, if you care about this world, before commencing with this command please MAKE A BACKUP. To acknowledge you've read this, do ?WeaponsDLC_RELOAD_ADDON do_as_i_say, if you want to go back now, do ?WeaponsDLC_RELOAD_ADDON", false, false, user_peer_id)
						playerData.isDoAsISay.user_peer_id = not playerData.isDoAsISay.user_peer_id
					end

				elseif command == "?WDLCI" or command == "?WeaponsDLCInfo" then
					wpDLCDebug("------ Improved Conquest Mode Info ------", false, false, user_peer_id)
					wpDLCDebug("Version: "..IMPROVED_CONQUEST_VERSION, false, false, user_peer_id)
					if g_savedata.info.has_default_addon then
						wpDLCDebug("Has default conquest mode addon enabled, this will cause issues and errors!", false, true, user_peer_id)
					end
					wpDLCDebug("World Creation Version: "..g_savedata.info.creation_version, false, false, user_peer_id)
					wpDLCDebug("Times Addon Was Fully Reloaded: "..tostring(g_savedata.info.full_reload_versions and #g_savedata.info.full_reload_versions or 0), false, false, user_peer_id)
					if g_savedata.info.full_reload_versions and #g_savedata.info.full_reload_versions ~= nil and #g_savedata.info.full_reload_versions ~= 0 then
						wpDLCDebug("Fully Reloaded Versions: ", false, false, user_peer_id)
						for i = 1, #g_savedata.info.full_reload_versions do
							wpDLCDebug(g_savedata.info.full_reload_versions[i], false, false, user_peer_id)
						end
					end
				elseif command == "?WDLCAM" or command == "?WeaponsDLCAIModifier" then
					if arg1 then
						sm.debug(user_peer_id, arg1, arg2, arg3, arg4)
					else
						wpDLCDebug("you need to specify which type to debug!", false, true, user_peer_id)
					end
				elseif command == "?WDLCDV" or command == "?WeaponsDLCDeleteVehicle" then
					if arg1 then
						if arg1 == "all" then
							for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
								for vehicle_id, vehicle_object in pairs(squad.vehicles) do
									killVehicle(squad_index, vehicle_id, true, true)
									wpDLCDebug("Sucessfully deleted vehicle "..vehicle_id, false, false, user_peer_id)
								end
							end
						else
							local found_vehicle = false
							for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
								for vehicle_id, vehicle_object in pairs(squad.vehicles) do
									if vehicle_id == tonumber(arg1) then
										found_vehicle = true
										killVehicle(squad_index, vehicle_id, true, true)
										wpDLCDebug("Sucessfully deleted vehicle "..vehicle_id.." name: "..vehicle_object.name, false, false, user_peer_id)
									end
								end
							end
							if not found_vehicle then
								wpDLCDebug("I was unable to find the vehicle with the id of "..arg1, false, true, user_peer_id)
							end
						end
					else
						wpDLCDebug("invalid syntax! you must either choose a vehicle id, or \"all\" to remove all enemy ai vehicles", false, true, user_peer_id) 
					end
				elseif command == "?WDLCSI" or command == "?WeaponsDLCScoutIsland" then
					if arg1 then
						if arg2 then
							if tonumber(arg2) then
								if g_savedata.ai_knowledge.scout[string.gsub(arg1, "_", " ")] then
									g_savedata.ai_knowledge.scout[string.gsub(arg1, "_", " ")].scouted = (math.clamp(tonumber(arg2), 0, 100)/100) * scout_requirement
								else
									wpDLCDebug("Unknown island: "..string.gsub(arg1, "_", " "), false, true, user_peer_id)
								end
							else
								wpDLCDebug("arg 2 has to be a number! unknown value: "..arg2, false, true, user_peer_id)
							end
						else
							wpDLCDebug("invalid syntax! you must specify the scout level to set it to (0-100)", false, true, user_peer_id)
						end
					else
						wpDLCDebug("invalid syntax! you must specify the island and the scout level (0-100) to set it to!", false, true, user_peer_id)
					end
				else
					wpDLCDebug("unknown command "..command, false, true, user_peer_id)
				end
			else
				wpDLCDebug("You do not have permission to execute "..command..".", false, true, user_peer_id)
			end
		end
	end
end

function captureIsland(island, override, peer_id)
	local faction_to_set = nil

	if not override then
		if island.capture_timer <= 0 and island.faction ~= FACTION_AI then -- Player Lost Island
			faction_to_set = FACTION_AI
		elseif island.capture_timer >= g_savedata.settings.CAPTURE_TIME and island.faction ~= FACTION_PLAYER then -- Player Captured Island
			faction_to_set = FACTION_PLAYER
		end
	end

	-- set it to the override, otherwise if its supposted to be capped then set it to the specified, otherwise set it to ignore
	faction_to_set = override or faction_to_set or "ignore"

	-- set it to ai
	if faction_to_set == FACTION_AI then
		island.capture_timer = 0
		island.faction = FACTION_AI
		g_savedata.is_attack = false
		updatePeerIslandMapData(-1, island)

		if peer_id then
			name = s.getPlayerName(peer_id)
			s.notify(-1, "ISLAND CAPTURED", "The enemy has captured an island. (set manually by "..name.." via command)", 3)
		else
			s.notify(-1, "ISLAND CAPTURED", "The enemy has captured an island.", 3)
		end

		island.is_scouting = false
		g_savedata.ai_knowledge.scout[island.name].scouted = scout_requirement

		sm.train(REWARD, "defend", 4)
		sm.train(PUNISH, "attack", 5)

		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			if (squad.command == COMMAND_ATTACK or squad.command == COMMAND_STAGE) and island.transform == squad.target_island.transform then
				setSquadCommand(squad, COMMAND_NONE) -- free squads from objective
			end
		end
	-- set it to player
	elseif faction_to_set == FACTION_PLAYER then
		island.capture_timer = g_savedata.settings.CAPTURE_TIME
		island.faction = FACTION_PLAYER
		updatePeerIslandMapData(-1, island)

		if peer_id then
			name = s.getPlayerName(peer_id)
			s.notify(-1, "ISLAND CAPTURED", "Successfully captured an island. (set manually by "..name.." via command)", 4)
		else
			s.notify(-1, "ISLAND CAPTURED", "Successfully captured an island.", 4)
		end

		g_savedata.ai_knowledge.scout[island.name].scouted = 0

		sm.train(REWARD, "defend", 4)
		sm.train(PUNISH, "attack", 2)

		-- update vehicles looking to resupply
		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			if squad_index == RESUPPLY_SQUAD_INDEX then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					resetPath(vehicle_object)
				end
			end
		end
	-- set it to neutral
	elseif faction_to_set == FACTION_NEUTRAL then
		island.capture_timer = g_savedata.settings.CAPTURE_TIME/2
		island.faction = FACTION_NEUTRAL
		updatePeerIslandMapData(-1, island)

		if peer_id then
			name = s.getPlayerName(peer_id)
			s.notify(-1, "ISLAND SET NEUTRAL", "Successfully set an island to neutral. (set manually by "..name.." via command)", 1)
		else
			s.notify(-1, "ISLAND SET NEUTRAL", "Successfully set an island to neutral.", 1)
		end

		island.is_scouting = false
		g_savedata.ai_knowledge.scout[island.name].scouted = 0

		-- update vehicles looking to resupply
		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			if squad_index == RESUPPLY_SQUAD_INDEX then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					resetPath(vehicle_object)
				end
			end
		end
	elseif island.capture_timer > g_savedata.settings.CAPTURE_TIME then -- if its over 100% island capture
		island.capture_timer = g_savedata.settings.CAPTURE_TIME
	elseif island.capture_timer < 0 then -- if its less than 0% island capture
		island.capture_timer = 0
	end
end


function onPlayerJoin(steam_id, name, peer_id)
	if g_savedata.info.has_default_addon then
		wpDLCDebug("WARNING: The default addon for conquest mode was left enabled! This will cause issues and bugs! Please create a new world with the default addon disabled!", false, true, peer_id)
	end
	if is_dlc_weapons then
		for island_index, island in pairs(g_savedata.controllable_islands) do
			updatePeerIslandMapData(peer_id, island)
		end

		local ts_x, ts_y, ts_z = m.position(g_savedata.ai_base_island.transform)
		s.removeMapObject(peer_id, g_savedata.ai_base_island.map_id)
		s.addMapObject(peer_id, g_savedata.ai_base_island.map_id, 0, 10, ts_x, ts_z, 0, 0, 0, 0, g_savedata.ai_base_island.name.." ("..g_savedata.ai_base_island.faction..")", 1, "", 255, 0, 0, 255)

		local ts_x, ts_y, ts_z = m.position(g_savedata.player_base_island.transform)
		s.removeMapObject(peer_id, g_savedata.player_base_island.map_id)
		s.addMapObject(peer_id, g_savedata.player_base_island.map_id, 0, 10, ts_x, ts_z, 0, 0, 0, 0, g_savedata.player_base_island.name.." ("..g_savedata.player_base_island.faction..")", 1, "", 0, 255, 0, 255)
	end
end

function onVehicleDamaged(incoming_vehicle_id, amount, x, y, z, body_id)
	if is_dlc_weapons then
		vehicleData = s.getVehicleData(incoming_vehicle_id)
		local player_vehicle = g_savedata.player_vehicles[incoming_vehicle_id]

		if player_vehicle ~= nil then
			local damage_prev = player_vehicle.current_damage
			player_vehicle.current_damage = player_vehicle.current_damage + amount

			if damage_prev <= player_vehicle.damage_threshold and player_vehicle.current_damage > player_vehicle.damage_threshold then
				player_vehicle.death_pos = player_vehicle.transform
			end

			-- attempts to estimate which vehicles did the damage, as to not favour the vehicles that are closest
			-- give it to all vehicles within 3000m of the player, and that are targeting the player's vehicle
			local valid_ai_vehicles = {}
			for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if vehicle_object.target_vehicle_id == incoming_vehicle_id then -- if the ai vehicle is targeting the vehicle which was damaged
						if xzDistance(player_vehicle.transform, vehicle_object.transform) <= 3000 then -- if the ai vehicle is 3000m or less away from the player
							valid_ai_vehicles[vehicle_id] = vehicle_object
							if not vehicle_object.damage_dealt[incoming_vehicle_id] then vehicle_object.damage_dealt[incoming_vehicle_id] = 0 end
						end
					end
				end
			end
			-- <valid ai> = all the enemy ai vehicles within 3000m of the player, and that are targeting the player
			-- <ai amount> = number of <valid ai>
			--
			-- for all the <valid ai>, add the damage dealt to the player / <ai_amount> to their damage dealt property
			-- this is used to tell if that vehicle, the type of vehicle, its strategy and its role was effective
			for vehicle_id, vehicle_object in pairs(valid_ai_vehicles) do
				vehicle_object.damage_dealt[incoming_vehicle_id] = vehicle_object.damage_dealt[incoming_vehicle_id] + amount/tableLength(valid_ai_vehicles)
			end
		end

		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			for vehicle_id, vehicle_object in pairs(squad.vehicles) do
				if vehicle_id == incoming_vehicle_id and body_id == 0 then
					if vehicle_object.current_damage == nil then vehicle_object.current_damage = 0 end
					local damage_prev = vehicle_object.current_damage
					vehicle_object.current_damage = vehicle_object.current_damage + amount

					local enemy_hp = g_savedata.settings.ENEMY_HP
					if vehicle_object.size == "large" then
						enemy_hp = enemy_hp * 4
					elseif vehicle_object.size == "medium" then
						enemy_hp = enemy_hp * 2
					end

					if g_savedata.settings.SINKING_MODE or vehicle_object.capabilities.gps_missiles then
						enemy_hp = enemy_hp * 8
					end

					if not g_savedata.settings.SINKING_MODE or g_savedata.settings.SINKING_MODE and hasTag(vehicleData.tags, "type=wep_land") or g_savedata.settings.SINKING_MODE and hasTag(vehicleData.tags, "type=wep_turret") then

						if damage_prev <= (enemy_hp * 2) and vehicle_object.current_damage > (enemy_hp * 2) then
							killVehicle(squad_index, vehicle_id, true)
						elseif damage_prev <= enemy_hp and vehicle_object.current_damage > enemy_hp then
							killVehicle(squad_index, vehicle_id, false)
						end
					end
				end
			end
		end
	end
end

function onVehicleTeleport(vehicle_id, peer_id, x, y, z)
	if is_dlc_weapons then
		if g_savedata.player_vehicles[vehicle_id] ~= nil then
			g_savedata.player_vehicles[vehicle_id].current_damage = 0
		end
	end
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, cost)
	if is_dlc_weapons then
		if peer_id ~= -1 then
			-- player spawned vehicle
			g_savedata.player_vehicles[vehicle_id] = {
				current_damage = 0, 
				damage_threshold = 100, 
				death_pos = nil, 
				map_id = s.getMapID()
			}
		end
	end
end

function onVehicleDespawn(vehicle_id, peer_id)
	if is_dlc_weapons then
		if g_savedata.player_vehicles[vehicle_id] ~= nil then
			g_savedata.player_vehicles[vehicle_id] = nil
		end
	end

	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for ai_vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if vehicle_id == ai_vehicle_id then
				cleanVehicle(squad_index, vehicle_id)
			end
		end
	end
end

function cleanVehicle(squad_index, vehicle_id)

	local vehicle_object = g_savedata.ai_army.squadrons[squad_index].vehicles[vehicle_id]

	wpDLCDebug("cleaned vehicle: "..vehicle_id, true, false)
	for k, v in pairs(playerData.isDebugging) do
		if playerData.isDebugging[k] then

			s.removeMapObject(k ,vehicle_object.map_id)
			s.removeMapLine(k ,vehicle_object.map_id)
			for i = 1, #vehicle_object.path - 1 do
				local waypoint = vehicle_object.path[i]
				s.removeMapLine(k, waypoint.ui_id)
			end
		end
	end

	if vehicle_object.ai_type == AI_TYPE_TURRET and vehicle_object.spawnbox_index ~= nil then
		for island_index, island in pairs(g_savedata.controllable_islands) do		
			if island.name == vehicle_object.home_island then
				island.zones[vehicle_object.spawnbox_index].is_spawned = false
			end
		end
	end

	for _, survivor in pairs(vehicle_object.survivors) do
		s.despawnObject(survivor.id, true)
	end

	if vehicle_object.fire_id ~= nil then
		s.despawnObject(vehicle_object.fire_id, true)
	end

	g_savedata.ai_army.squadrons[squad_index].vehicles[vehicle_id] = nil

	if squad_index ~= RESUPPLY_SQUAD_INDEX then
		if tableLength(g_savedata.ai_army.squadrons[squad_index].vehicles) <= 0 then -- squad has no more vehicles
			g_savedata.ai_army.squadrons[squad_index] = nil

			for island_index, island in pairs(g_savedata.controllable_islands) do
				if island.assigned_squad_index == squad_index then
					island.assigned_squad_index = -1
				end
			end
		end
	end
end

function onVehicleUnload(incoming_vehicle_id)
	if is_dlc_weapons then
		wpDLCDebug("onVehicleUnload: "..incoming_vehicle_id, true, false)

		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			for vehicle_id, vehicle_object in pairs(squad.vehicles) do
				if incoming_vehicle_id == vehicle_id then
					if vehicle_object.is_killed == true then
						cleanVehicle(squad_index, vehicle_id)
					else
						wpDLCDebug("onVehicleUnload: set vehicle pseudo: "..vehicle_id, true, false)
						if not vehicle_object.name then vehicle_object.name = "nil" end
						wpDLCDebug("(onVehicleUnload) vehicle name: "..vehicle_object.name, true, false)
						vehicle_object.state.is_simulating = false
					end
				end
			end
		end
	end
end

function setKeypadTargetCoords(vehicle_id, vehicle_object, squad)
	local squad_vision = squadGetVisionData(squad)
	local target = nil
	if vehicle_object.target_player_id ~= -1 and vehicle_object.target_player_id and squad_vision.visible_players_map[vehicle_object.target_player_id] then
		target = squad_vision.visible_players_map[vehicle_object.target_player_id].obj
	elseif vehicle_object.target_vehicle_id ~= -1 and vehicle_object.target_vehicle_id and squad_vision.visible_vehicles_map[vehicle_object.target_vehicle_id] then
		target = squad_vision.visible_vehicles_map[vehicle_object.target_vehicle_id].obj
	end
	if target then
		tx, ty, tz = matrix.position(target.last_known_pos)
		s.setVehicleKeypad(vehicle_id, "AI_GPS_MISSILE_TARGET_X", tx)
		s.setVehicleKeypad(vehicle_id, "AI_GPS_MISSILE_TARGET_Y", ty)
		s.setVehicleKeypad(vehicle_id, "AI_GPS_MISSILE_TARGET_Z", tz)
		s.pressVehicleButton(vehicle_id, "AI_GPS_MISSILE_FIRE")
	end
end

function setLandTarget(vehicle_id, vehicle_object)
	if vehicle_object.state.is_simulating and vehicle_id and vehicle_object.path[1].x then
		s.setVehicleKeypad(vehicle_id, "AI_WAYPOINT_LAND_X", vehicle_object.path[1].x)
		s.setVehicleKeypad(vehicle_id, "AI_WAYPOINT_LAND_Z", vehicle_object.path[1].z)
		s.setVehicleKeypad(vehicle_id, "AI_WAYPOINT_FINAL_LAND_X", vehicle_object.path[#vehicle_object.path].x)
		s.setVehicleKeypad(vehicle_id, "AI_WAYPOINT_FINAL_LAND_Z", vehicle_object.path[#vehicle_object.path].z)
		local terrain_type = 2
		if vehicle_object.terrain_type == "road" then
			terrain_type = 1
		elseif vehicle_object.terrain_type == "bridge" then
			terrain_type = 3
		end

		local is_aggressive = 0
		if vehicle_object.is_aggressive == "aggressive" then
			is_aggressive = 1
		end
		s.setVehicleKeypad(vehicle_id, "AI_ROAD_TYPE", terrain_type)
		s.setVehicleKeypad(vehicle_id, "AI_AGR_STATUS", is_aggressive)
	end
end

function onVehicleLoad(incoming_vehicle_id)
	if is_dlc_weapons then
		wpDLCDebug("(onVehicleLoad) vehicle loading! id: "..incoming_vehicle_id, true, false)

		if g_savedata.player_vehicles[incoming_vehicle_id] ~= nil then
			local player_vehicle_data = s.getVehicleData(incoming_vehicle_id)
			g_savedata.player_vehicles[incoming_vehicle_id].damage_threshold = player_vehicle_data.voxels / 4
			g_savedata.player_vehicles[incoming_vehicle_id].transform = s.getVehiclePos(incoming_vehicle_id)
		end

		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			for vehicle_id, vehicle_object in pairs(squad.vehicles) do
				if incoming_vehicle_id == vehicle_id then
					wpDLCDebug("(onVehicleLoad) set vehicle simulating: "..vehicle_id, true, false)
					if not vehicle_object.name then vehicle_object.name = "nil" end
					wpDLCDebug("(onVehicleLoad) vehicle name: "..vehicle_object.name, true, false)
					vehicle_object.state.is_simulating = true
					vehicle_object.transform = s.getVehiclePos(vehicle_id)

					if vehicle_object.is_resupply_on_load then
						vehicle_object.is_resupply_on_load = false
						reload(vehicle_id)
					end

					for i, char in pairs(vehicle_object.survivors) do
						if vehicle_object.ai_type == AI_TYPE_TURRET then
							--Gunners
							s.setCharacterSeated(char.id, vehicle_id, "Gunner ".. i)
							local c = s.getCharacterData(char.id)
							s.setCharacterData(char.id, c.hp, true, true)
						else
							if i == 1 then
								if vehicle_object.ai_type == AI_TYPE_BOAT or vehicle_object.ai_type == AI_TYPE_LAND then
									s.setCharacterSeated(char.id, vehicle_id, "Captain")
								else
									s.setCharacterSeated(char.id, vehicle_id, "Pilot")
								end
								local c = s.getCharacterData(char.id)
								s.setCharacterData(char.id, c.hp, true, true)
							else
								--Gunners
								s.setCharacterSeated(char.id, vehicle_id, "Gunner ".. (i - 1))
								local c = s.getCharacterData(char.id)
								s.setCharacterData(char.id, c.hp, true, true)
							end
						end
					end
					if vehicle_object.ai_type == AI_TYPE_LAND then
						if(#vehicle_object.path >= 1) then
							setLandTarget(vehicle_id, vehicle_object)
						end
						if g_savedata.terrain_scanner_links[vehicle_id] == nil then
							local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_object.transform)
							local get_terrain_matrix = m.translation(vehicle_x, 1000, vehicle_z)
							local terrain_object, success = s.spawnAddonComponent(get_terrain_matrix, g_savedata.terrain_scanner_prefab.playlist_index, g_savedata.terrain_scanner_prefab.location_index, g_savedata.terrain_scanner_prefab.object_index, 0)
							if success then
								s.setVehiclePos(vehicle_id, m.translation(vehicle_x, 0, vehicle_z))
								g_savedata.terrain_scanner_links[vehicle_id] = terrain_object.id
							else
								wpDLCDebug("Unable to spawn terrain height checker!", true, true)
							end
						elseif g_savedata.terrain_scanner_links[vehicle_id] == "Just Teleported" then
							g_savedata.terrain_scanner_links[vehicle_id] = nil
						end
					elseif vehicle_object.ai_type == AI_TYPE_BOAT then
						local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_object.transform)
						if vehicle_y > 10 then -- if its above y 10
							local playerList = s.getPlayers()
							local is_player_close = false
							-- checks if any players are within 750m of the vehicle
							for _, player in pairs(playerList) do
								local player_transform = s.getPlayerPos(player.id)
								if m.distance(player_transform, vehicle_object.transform) < 250 then
									is_player_close = true
								end
							end
							if not is_player_close then
								wpDLCDebug("a vehicle was removed as it tried to spawn in the air!", true, false)
								killVehicle(squad_index, vehicle_id, true, true) -- delete vehicle
							end
						end
					end
					refuel(vehicle_id)
					return
				end
			end
		end
	end
end

function resetPath(vehicle_object)
	for _, v in pairs(vehicle_object.path) do
		s.removeMapID(0, v.ui_id)
	end

	vehicle_object.path = {}
end

function addPath(vehicle_object, target_dest)
	if(vehicle_object.ai_type == AI_TYPE_TURRET) then vehicle_object.state.s = "stationary" return end

	if(vehicle_object.ai_type == AI_TYPE_BOAT) then
		local dest_x, dest_y, dest_z = m.position(target_dest)

		local path_start_pos = nil

		if #vehicle_object.path > 0 then
			local waypoint_end = vehicle_object.path[#vehicle_object.path]
			path_start_pos = m.translation(waypoint_end.x, waypoint_end.y, waypoint_end.z)
		else
			path_start_pos = vehicle_object.transform
		end

		local path_list = s.pathfindOcean(path_start_pos, m.translation(dest_x, 0, dest_z))
		for path_index, path in pairs(path_list) do
			table.insert(vehicle_object.path, { x =  path.x + math.random(-50, 50), y = 0, z = path.z + math.random(-50, 50), ui_id = s.getMapID() })
		end
	elseif vehicle_object.ai_type == AI_TYPE_LAND then
		local dest_x, dest_y, dest_z = m.position(target_dest)

		local path_start_pos = nil

		if #vehicle_object.path > 0 then
			local waypoint_end = vehicle_object.path[#vehicle_object.path]
			path_start_pos = m.translation(waypoint_end.x, waypoint_end.y, waypoint_end.z)
		else
			path_start_pos = vehicle_object.transform
		end

		start_x, start_y, start_z = m.position(vehicle_object.transform)
 
		local path_list = s.pathfindOcean(path_start_pos, m.translation(dest_x, 1000, dest_z))
		for path_index, path in pairs(path_list) do
			veh_x, veh_y, veh_z = m.position(vehicle_object.transform)
			distance = m.distance(vehicle_object.transform, m.translation(path.x, veh_y, path.z))
			if path_index == 1 then
				wpDLCDebugVehicle(vehicle_object.id, "vehicle id: "..vehicle_object.id.." | distance from destination: "..m.distance(vehicle_object.transform, m.translation(dest_x, veh_y, dest_z)).." distance from path 1 to dest: "..m.distance(m.translation(dest_x, veh_y, dest_z), m.translation(path.x, veh_y, path.z)), true, false)
			end
			if path_index ~= 1 or #path_list == 1 or m.distance(vehicle_object.transform, m.translation(dest_x, veh_y, dest_z)) > m.distance(m.translation(dest_x, veh_y, dest_z), m.translation(path.x, veh_y, path.z)) and distance >= 7 then
				table.insert(vehicle_object.path, { x =  path.x, y = path.y, z = path.z, ui_id = s.getMapID() })
			end
		end
		setLandTarget(vehicle_id, vehicle_object)
	else
		local dest_x, dest_y, dest_z = m.position(target_dest)
		table.insert(vehicle_object.path, { x = dest_x, y = dest_y, z = dest_z, ui_id = s.getMapID() })
	end

	vehicle_object.state.s = VEHICLE_STATE_PATHING
end

function tickGamemode()
	if is_dlc_weapons then
		-- tick enemy base spawning
		g_savedata.ai_base_island.production_timer = g_savedata.ai_base_island.production_timer + 1
		if g_savedata.ai_base_island.production_timer > g_savedata.settings.AI_PRODUCTION_TIME_BASE then
			g_savedata.ai_base_island.production_timer = 0

			spawnTurret(g_savedata.ai_base_island)
			spawnAIVehicle()
		end

		for island_index, island in pairs(g_savedata.controllable_islands) do

			if island.ai_capturing == nil then
				island.ai_capturing = 0
				island.players_capturing = 0
			end

			-- spawn turrets at owned islands
			if island.faction == FACTION_AI and g_savedata.ai_base_island.production_timer == 1 then
				spawnTurret(island)
			end
			
			-- tick capture timers
			local tick_rate = 60
			if island.capture_timer >= 0 and island.capture_timer <= g_savedata.settings.CAPTURE_TIME then -- if the capture timers are within range of the min and max
				local playerList = s.getPlayers()
				
				-- does a check for how many enemy ai are capturing the island
				if island.capture_timer > 0 then
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						if squad.command == COMMAND_ATTACK then
							local target_island, origin_island = getObjectiveIsland()
							if target_island.name == island.name then
								for vehicle_id, vehicle_object in pairs(squad.vehicles) do
									if isTickID(vehicle_id, tick_rate) then
										if vehicle_object.role ~= "scout" then
											if m.distance(island.transform, vehicle_object.transform) < CAPTURE_RADIUS / 1.5 then
												island.ai_capturing = island.ai_capturing + 1
											elseif m.distance(island.transform, vehicle_object.transform) < CAPTURE_RADIUS and island.faction == FACTION_AI then
												island.ai_capturing = island.ai_capturing + 1
											end
										end
									end
								end
							end
						end
					end
				end

				-- does a check for how many players are capturing the island
				if g_savedata.settings.CAPTURE_TIME > island.capture_timer then -- if the % captured is not 100% or more
					for _, player in pairs(playerList) do
						if isTickID(player.id, tick_rate) then
							local player_transform = s.getPlayerPos(player.id)
							local flag_vehicle_transform = s.getVehiclePos(island.flag_vehicle.id)
							if m.distance(flag_vehicle_transform, player_transform) < 15 then -- if they are within 15 metres of the capture point
								island.players_capturing = island.players_capturing + 1
							elseif m.distance(flag_vehicle_transform, player_transform) < CAPTURE_RADIUS / 5 and island.faction == FACTION_PLAYER then -- if they are within CAPTURE_RADIUS / 5 metres of the capture point and if they own the point, this is their defending radius
								island.players_capturing = island.players_capturing + 1
							end
						end
					end
				end

				if isTickID(60, tick_rate) then
					if island.players_capturing > 0 and island.ai_capturing > 0 and g_savedata.settings.CONTESTED_MODE then -- if theres ai and players capping, and if contested mode is enabled
						if island.is_contested == false then -- notifies that an island is being contested
							s.notify(-1, "ISLAND CONTESTED", "An island is being contested!", 1)
							island.is_contested = true
							updatePeerIslandMapData(-1, island)
						end
					else
						island.is_contested = false
						if island.players_capturing > 0 then -- tick player progress if theres one or more players capping

							island.capture_timer = island.capture_timer + ((ISLAND_CAPTURE_AMOUNT_PER_SECOND * 5) * capture_speeds[math.min(island.players_capturing, 3)])
						elseif island.ai_capturing > 0 then -- tick AI progress if theres one or more ai capping
							island.capture_timer = island.capture_timer - (ISLAND_CAPTURE_AMOUNT_PER_SECOND * capture_speeds[math.min(island.ai_capturing, 3)])
						end
					end
					
					-- displays tooltip on vehicle
					local cap_percent = math.floor((island.capture_timer/g_savedata.settings.CAPTURE_TIME) * 100)
	
					if island.is_contested then -- if the point is contested (both teams trying to cap)
						s.setVehicleTooltip(island.flag_vehicle.id, "Contested: "..cap_percent.."%")
	
					elseif island.faction ~= FACTION_PLAYER then -- if the player doesn't own the point
	
						if island.ai_capturing == 0 and island.players_capturing == 0 then -- if nobody is capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Capture: "..cap_percent.."%")
	
						elseif island.ai_capturing == 0 then -- if players are capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Capturing: "..cap_percent.."%")
						else -- if ai is capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Losing: "..cap_percent.."%")
	
						end
					else -- if the player does own the point
	
						if island.ai_capturing == 0 and island.players_capturing == 0 then -- if nobody is capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Captured: "..cap_percent.."%")
	
						elseif island.ai_capturing == 0 then -- if players are capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Re-Capturing: "..cap_percent.."%")
	
						else -- if ai is capping the point
							s.setVehicleTooltip(island.flag_vehicle.id, "Losing: "..cap_percent.."%")
	
						end
					end

					-- resets amount capping
					island.ai_capturing = 0
					island.players_capturing = 0
					captureIsland(island)
				end
			end
		end

		if render_debug then
			if isTickID(60, 60) then
			
				local ts_x, ts_y, ts_z = m.position(g_savedata.ai_base_island.transform)
				s.removeMapObject(player_debugging_id, g_savedata.ai_base_island.map_id)

				local plane_count = 0
				local heli_count = 0
				local army_count = 0
				local land_count = 0
				local turret_count = 0
			
				for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
					for vehicle_id, vehicle_object in pairs(squad.vehicles) do
						if vehicle_object.ai_type ~= AI_TYPE_TURRET then army_count = army_count + 1 end
						if vehicle_object.ai_type == AI_TYPE_TURRET then turret_count = turret_count + 1 end
						if vehicle_object.ai_type == AI_TYPE_PLANE then plane_count = plane_count + 1 end
						if vehicle_object.ai_type == AI_TYPE_HELI then heli_count = heli_count + 1 end
						if vehicle_object.ai_type == AI_TYPE_LAND then land_count = land_count + 1 end
					end
				end

				local t, a = getObjectiveIsland()
				local debug_data = "Air_Staged: " .. tostring(g_is_air_ready) .. "\n"
				debug_data = debug_data .. "Sea_Staged: " .. tostring(g_is_boats_ready) .. "\n"
				debug_data = debug_data .. "Army_Count: " .. tostring(army_count) .. "\n"
				debug_data = debug_data .. "Land_Count: " .. tostring(land_count) .. "\n"
				debug_data = debug_data .. "Turret_Count: " .. tostring(turret_count) .. "\n"
				debug_data = debug_data .. "Squad Count: " .. tostring(g_count_squads) .. "\n"
				debug_data = debug_data .. "Attack Count: " .. tostring(g_count_attack) .. "\n"
				debug_data = debug_data .. "Patrol Count: " .. tostring(g_count_patrol) .. "\n"

				if t then
					debug_data = debug_data .. "Target: " .. t.name .. "\n"
				end
				if a then
					debug_data = debug_data .. " Ally: " .. a.name
				end
				for player_debugging_id, v in pairs(playerData.isDebugging) do
					if playerData.isDebugging[player_debugging_id] then
						s.addMapObject(player_debugging_id, g_savedata.ai_base_island.map_id, 0, 4, ts_x, ts_z, 0, 0, 0, 0, "Ai Base Island \n" .. g_savedata.ai_base_island.production_timer .. "/" .. g_savedata.settings.AI_PRODUCTION_TIME_BASE, 1, debug_data, 0, 0, 255, 255)

						local ts_x, ts_y, ts_z = m.position(g_savedata.player_base_island.transform)
						s.removeMapObject(player_debugging_id, g_savedata.player_base_island.map_id)
						s.addMapObject(player_debugging_id, g_savedata.player_base_island.map_id, 0, 4, ts_x, ts_z, 0, 0, 0, 0, "Player Base Island", 1, debug_data, 0, 0, 255, 255)
					end
				end
			end

			-- Render Island Info
			for island_index, island in pairs(g_savedata.controllable_islands) do
				if isTickID(island_index, 60) then
					updatePeerIslandMapData(-1, island)
					island.capture_timer_prev = island.capture_timer
					island.faction_prev = island.faction
				end
			end
		end
	end
end

function updatePeerIslandMapData(peer_id, island, is_reset)
	if is_dlc_weapons then
		local ts_x, ts_y, ts_z = m.position(island.transform)
		s.removeMapObject(peer_id, island.map_id)
		if not is_reset then
			local cap_percent = math.floor((island.capture_timer/g_savedata.settings.CAPTURE_TIME) * 100)
			local extra_title = ""
			local r = 75
			local g = 75
			local b = 75
			if island.is_contested then
				r = 255
				g = 255
				b = 0
				extra_title = " CONTESTED"
			elseif island.faction == FACTION_AI then
				r = 255
				g = 0
				b = 0
			elseif island.faction == FACTION_PLAYER then
				r = 0
				g = 255
				b = 0
			end

			if not render_debug then
				s.addMapObject(peer_id, island.map_id, 0, 9, ts_x, ts_z, 0, 0, 0, 0, island.name.." ("..island.faction..")"..extra_title, 1, cap_percent.."%", r, g, b, 255)
			else
				for player_debugging_id, v in pairs(playerData.isDebugging) do
					if playerData.isDebugging[player_debugging_id] then
						local debug_data = ""
						debug_data = debug_data.."\nScout Progress: "..math.floor(g_savedata.ai_knowledge.scout[island.name].scouted/scout_requirement*100).."%"
						debug_data = debug_data.."\n\nNumber of AI Capturing: "..island.ai_capturing
						debug_data = debug_data.."\nNumber of Players Capturing: "..island.players_capturing
						if island.faction == FACTION_AI then debug_data = debug_data.."\n\nNumber of defenders: "..island.defenders end

						
						s.addMapObject(player_debugging_id, island.map_id, 0, 9, ts_x, ts_z, 0, 0, 0, 0, island.name.." ("..island.faction..")"..extra_title, 1, cap_percent.."%"..debug_data, r, g, b, 255)
					end
				end
			end
		end
	end
end

function getSquadLeader(squad)
	for vehicle_id, vehicle_object in pairs(squad.vehicles) do
		return vehicle_id, vehicle_object
	end
	wpDLCDebug("warning: empty squad "..squad.ai_type.." detected", true, true)
	return nil
end

function getNearbySquad(transform, override_command)

	local closest_free_squad = nil
	local closest_free_squad_index = -1
	local closest_dist = 999999999

	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		if squad.command == COMMAND_NONE
		or squad.command == COMMAND_PATROL
		or override_command then

			local _, squad_leader = getSquadLeader(squad)
			local squad_vehicle_transform = squad_leader.transform
			local distance = m.distance(transform, squad_vehicle_transform)

			if distance < closest_dist then
				closest_free_squad = squad
				closest_free_squad_index = squad_index
				closest_dist = distance
			end
		end
	end

	return closest_free_squad, closest_free_squad_index
end

function tickAI()
	if is_dlc_weapons then

		-- allocate squads to islands
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if isTickID(island_index, 60) then
				if island.faction == FACTION_AI then
					if island.assigned_squad_index == -1 then
						local squad, squad_index = getNearbySquad(island.transform)

						if squad ~= nil then
							setSquadCommandDefend(squad, island)
							island.assigned_squad_index = squad_index
						end
					end
				end
			end
			if isTickID(island_index*15, time.minute/4) then -- every 15 seconds, update the amount of vehicles that are defending the base
				island.defenders = 0
				for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
					if squad.command == COMMAND_DEFEND or squad.command == COMMAND_TURRET then
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							if island.faction == FACTION_AI then
								if xzDistance(island.transform, vehicle_object.transform) < 1500 then
									island.defenders = island.defenders + 1
								end
							end
						end
					end
				end
			end 
		end

		-- allocate squads to engage or investigate based on vision
		for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
			if isTickID(squad_index, 60) then			
				if squad_index ~= RESUPPLY_SQUAD_INDEX then
					local squad_vision = squadGetVisionData(squad)
					if squad.command ~= COMMAND_SCOUT then
						if squad.command ~= COMMAND_ENGAGE and squad_vision:is_engage() then
							setSquadCommandEngage(squad)
						elseif squad.command ~= COMMAND_INVESTIGATE and squad_vision:is_investigate() then
							if #squad_vision.investigate_players > 0 then
								local investigate_player = squad_vision:getBestInvestigatePlayer()
								setSquadCommandInvestigate(squad, investigate_player.obj.last_known_pos)
							elseif #squad_vision.investigate_vehicles > 0 then
								local investigate_vehicle = squad_vision:getBestInvestigateVehicle()
								setSquadCommandInvestigate(squad, investigate_vehicle.obj.last_known_pos)
							end
						end
					end
				end
			end
		end

		if isTickID(0, 60) then
			g_count_squads = 0
			g_count_attack = 0
			g_count_patrol = 0

			for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
				if squad_index ~= RESUPPLY_SQUAD_INDEX then
					if squad.command ~= COMMAND_DEFEND and squad.ai_type ~= AI_TYPE_TURRET then
						g_count_squads = g_count_squads + 1
					end
		
					if squad.command == COMMAND_STAGE or squad.command == COMMAND_ATTACK then
						g_count_attack = g_count_attack + 1
					elseif squad.command == COMMAND_PATROL then
						g_count_patrol = g_count_patrol + 1
					end
				end
			end

			local objective_island, ally_island = getObjectiveIsland()

			if objective_island == nil then
				g_savedata.is_attack = false
			else
				if g_savedata.is_attack == false then
					if g_savedata.constructable_vehicles.attack.mod > -1 then -- if its above the threshold in order to attack
						if g_savedata.ai_knowledge.scout[objective_island.name].scouted >= scout_requirement then
							local boats_ready = 0
							local boats_total = 0
							local air_ready = 0
							local air_total = 0
							local land_ready = 0
							local land_total = 0
							objective_island.is_scouting = false

							for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
								if squad.command == COMMAND_PATROL or squad.command == COMMAND_DEFEND then
									if squad.role ~= "defend" and (air_total + boats_total) < MAX_ATTACKING_SQUADS then
										if squad.ai_type == AI_TYPE_BOAT or squad.ai_type == AI_TYPE_LAND then
											if squad.ai_type == AI_TYPE_BOAT and not hasTag(objective_island.tags, "no-access=boat") or squad.ai_type == AI_TYPE_LAND then
												setSquadCommandStage(squad, ally_island)
											end
										else
											setSquadCommandStage(squad, ally_island)
										end
									end
								elseif squad.command == COMMAND_STAGE then
									local _, squad_leader = getSquadLeader(squad)
									local squad_leader_transform = squad_leader.transform

									if squad.ai_type == AI_TYPE_BOAT then
										boats_total = boats_total + 1

										local air_dist = m.distance(objective_island.transform, ally_island.transform)
										local dist = m.distance(squad_leader_transform, objective_island.transform)
										local air_sea_speed_factor = AI_SPEED_PSEUDO_BOAT/AI_SPEED_PSEUDO_PLANE

										if dist < air_dist * air_sea_speed_factor then
											boats_ready = boats_ready + 1
										end
									elseif squad.ai_type == AI_TYPE_LAND then
										land_total = land_total + 1

										local air_dist = m.distance(objective_island.transform, ally_island.transform)
										local dist = m.distance(squad_leader_transform, objective_island.transform)
										local air_sea_speed_factor = AI_SPEED_PSEUDO_LAND/AI_SPEED_PSEUDO_PLANE

										if dist < air_dist * air_sea_speed_factor then
											land_ready = land_ready + 1
										end
									else
										air_total = air_total + 1

										local dist = m.distance(squad_leader_transform, ally_island.transform)
										if dist < 2000 then
											air_ready = air_ready + 1
										end
									end
								end
							end
				
							g_is_air_ready = hasTag(objective_island.tags, "no-access=boat") or air_total == 0 or air_ready / air_total >= 0.5
							g_is_boats_ready = hasTag(objective_island.tags, "no-access=boat") or boats_total == 0 or boats_ready / boats_total >= 0.25
							wpDLCDebug("is air ready?"..tostring(g_is_air_ready))
							wpDLCDebug("is boat ready?"..tostring(g_is_boats_ready))
							local is_attack = (g_count_attack / g_count_squads) >= 0.25 and g_count_attack >= MIN_ATTACKING_SQUADS and g_is_boats_ready and g_is_air_ready
				
							if is_attack then
								g_savedata.is_attack = is_attack
				
								for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
									if squad.command == COMMAND_STAGE then
										if not hasTag(objective_island.tags, "no-access=boat") and squad.ai_type == AI_TYPE_BOAT then -- makes sure boats can attack that island
											setSquadCommandAttack(squad, objective_island)
										end
									end
								end
							else
								for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
									if squad.command == COMMAND_NONE and (air_total + boats_total) < MAX_ATTACKING_SQUADS then
										if squad.ai_type == AI_TYPE_BOAT then -- send boats ahead since they are slow
											if not hasTag(objective_island.tags, "no-access=boat") then -- if boats can attack that island
												setSquadCommandStage(squad, objective_island)
											end
										else
											setSquadCommandStage(squad, ally_island)
										end
									end
								end
							end
						else -- if they've yet to fully scout the base
							local scout_exists = false
							if not objective_island.is_scouting then
								for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
									for vehicle_index, vehicle in pairs(squad.vehicles) do
										if vehicle.role == "scout" then
											scout_exists = true
										end
									end
								end
								if not scout_exists then -- if a scout vehicle does not exist
									wpDLCDebug("attempting to spawn scout vehicle...", false, false)
									local spawned = spawnAIVehicle("scout")
									if spawned then
										wpDLCDebug("scout vehicle spawned!")
										objective_island.is_scouting = true
										for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
											if squad.command == COMMAND_SCOUT then
												setSquadCommandScout(squad)
											end
										end
									else
										wpDLCDebug("Failed to spawn scout vehicle!", false, false)
									end
								end
							end
						end
					else -- if they've not hit the threshold to attack
						if objective_island.is_scouting then -- if theres still a scout plane scouting the island
							for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
								if squad.command == COMMAND_SCOUT then
									setSquadCommand(squad, COMMAND_DEFEND)
								end
							end
						end
					end
				else
					local is_disengage = (g_count_attack / g_count_squads) < 0.25
		
					if is_disengage then
						g_savedata.is_attack = false
		
						for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
							if squad.command == COMMAND_ATTACK then
								if squad.ai_type == AI_TYPE_BOAT and not hasTag(objective_island.tags, "no-access=boat") or squad.ai_type ~= AI_TYPE_BOAT then
									setSquadCommandStage(squad, ally_island)
								end
							end
						end
					end
				end
			end

			-- assign squads to patrol
			local allied_islands = getAlliedIslands()

			for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
				if squad.command == COMMAND_NONE then
					if #allied_islands > 0 then
						if (g_count_patrol / g_count_squads) < 0.5 then
							g_count_patrol = g_count_patrol + 1
							setSquadCommandPatrol(squad, allied_islands[math.random(1, #allied_islands)])
						else
							setSquadCommandDefend(squad, allied_islands[math.random(1, #allied_islands)])
						end
					else
						setSquadCommandPatrol(squad, g_savedata.ai_base_island)
					end
				end
			end
		end
	end
end

function getAlliedIslands()
	local alliedIslandIndexes = {}
	for island_index, island in pairs(g_savedata.controllable_islands) do
		if island.faction == FACTION_AI then
			table.insert(alliedIslandIndexes, island)
		end
	end
	return alliedIslandIndexes
end

---@param ignore_scouted boolean true if you want to ignore islands that are already fully scouted
---@return table target_island returns the island which the ai should target
---@return table origin_island returns the island which the ai should attack from
function getObjectiveIsland(ignore_scouted)
	local origin_island = nil
	local target_island = nil
	local target_best_distance = nil
	for island_index, island in pairs(g_savedata.controllable_islands) do
		if island.faction ~= FACTION_AI then
			for ai_island_index, ai_island in pairs(g_savedata.controllable_islands) do
				if ai_island.faction == FACTION_AI or ignore_scouted and g_savedata.ai_knowledge.scout[island.name].scouted >= scout_requirement then
					if not ignore_scouted or g_savedata.ai_knowledge.scout[island.name].scouted < scout_requirement then
						if not target_island then
							origin_island = ai_island
							target_island = island
							if island.faction == FACTION_PLAYER then
								target_best_distance = xzDistance(ai_island.transform, island.transform)/1.5
							else
								target_best_distance = xzDistance(ai_island.transform, island.transform)
							end
						elseif island.faction == FACTION_PLAYER then -- if the player owns the island we are checking
							if target_island.faction == FACTION_PLAYER and xzDistance(ai_island.transform, island.transform) < target_best_distance then -- if the player also owned the island that we detected was the best to attack
								origin_island = ai_island
								target_island = island
								target_best_distance = xzDistance(ai_island.transform, island.transform)
							elseif target_island.faction ~= FACTION_PLAYER and xzDistance(ai_island.transform, island.transform)/1.5 < target_best_distance then -- if the player does not own the best match for an attack target so far
								origin_island = ai_island
								target_island = island
								target_best_distance = xzDistance(ai_island.transform, island.transform)/1.5
							end
						elseif island.faction ~= FACTION_PLAYER and xzDistance(ai_island.transform, island.transform) < target_best_distance then -- if the player does not own the island we are checking
							origin_island = ai_island
							target_island = island
							target_best_distance = xzDistance(ai_island.transform, island.transform)
						end
					end
				end
			end
		end
	end
	if not target_island then
		origin_island = g_savedata.ai_base_island
		for island_index, island in pairs(g_savedata.controllable_islands) do
			if island.faction ~= FACTION_AI or ignore_scouted and g_savedata.ai_knowledge.scout[island.name].scouted >= scout_requirement then
				if not ignore_scouted or g_savedata.ai_knowledge.scout[island.name].scouted < scout_requirement then
					if not target_island then
						target_island = island
						if island.faction == FACTION_PLAYER then
							target_best_distance = xzDistance(origin_island.transform, island.transform)/1.5
						else
							target_best_distance = xzDistance(origin_island.transform, island.transform)
						end
					elseif island.faction == FACTION_PLAYER then
						if target_island.faction == FACTION_PLAYER and xzDistance(origin_island.transform, island.transform) < target_best_distance then -- if the player also owned the island that we detected was the best to attack
							target_island = island
							target_best_distance = xzDistance(origin_island.transform, island.transform)
						elseif target_island.faction ~= FACTION_PLAYER and xzDistance(origin_island.transform, island.transform)/1.5 < target_best_distance then -- if the player does not own the best match for an attack target so far
							target_island = island
							target_best_distance = xzDistance(origin_island.transform, island.transform)/1.5
						end
					elseif island.faction ~= FACTION_PLAYER and xzDistance(origin_island.transform, island.transform) < target_best_distance then -- if the player does not own the island we are checking
						target_island = island
						target_best_distance = xzDistance(origin_island.transform, island.transform)
					end
				end
			end
		end
	end
	return target_island, origin_island
end

function getResupplyIsland(ai_vehicle_transform)
	local closest = g_savedata.ai_base_island
	local closest_dist = m.distance(ai_vehicle_transform, g_savedata.ai_base_island.transform)

	for island_index, island in pairs(g_savedata.controllable_islands) do
		if island.faction == FACTION_AI then
			local distance = m.distance(ai_vehicle_transform, island.transform)

			if distance < closest_dist then
				closest = island
				closest_dist = distance
			end
		end
	end

	return closest
end

function addToSquadron(vehicle_object)
	local new_squad = nil

	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		if squad_index ~= RESUPPLY_SQUAD_INDEX then -- do not automatically add to resupply squadron
			if squad.ai_type == vehicle_object.ai_type then
				local _, squad_leader = getSquadLeader(squad)
				if squad.ai_type ~= AI_TYPE_TURRET or vehicle_object.home_island == squad_leader.home_island then
					if vehicle_object.role ~= "scout" and squad.ai_type ~= "scout" then
						if tableLength(squad.vehicles) < MAX_SQUAD_SIZE then
							squad.vehicles[vehicle_object.id] = vehicle_object
							new_squad = squad
							break
						end
					end
				end
			end
		end
	end

	if new_squad == nil then
		new_squad = { 
			command = COMMAND_NONE, 
			ai_type = vehicle_object.ai_type, 
			role = vehicle_object.role,
			vehicles = {}, 
			target_island = nil,
			target_players = {},
			target_vehicles = {},
			investigate_transform = nil,
		}

		new_squad.vehicles[vehicle_object.id] = vehicle_object
		table.insert(g_savedata.ai_army.squadrons, new_squad)
	end

	squadInitVehicleCommand(new_squad, vehicle_object)
	return new_squad
end

function killVehicle(squad_index, vehicle_id, instant, delete)

	local vehicle_object = g_savedata.ai_army.squadrons[squad_index].vehicles[vehicle_id]

	if vehicle_object.is_killed ~= true or instant then
		wpDLCDebug(vehicle_id.." from squad "..squad_index.." is out of action", true, false)
		vehicle_object.is_killed = true
		vehicle_object.death_timer = 0

		-- change ai spawning modifiers
		if not delete then -- if the vehicle was not forcefully despawned
			local ai_damaged = vehicle_object.current_damage or 0
			local ai_damage_dealt = 1
			for vehicle_id, damage in pairs(vehicle_object.damage_dealt) do
				ai_damage_dealt = ai_damage_dealt + damage
			end

			local constructable_vehicle_id = sm.getConstructableVehicleID(vehicle_object.role, vehicle_object.ai_type, vehicle_object.strategy, sm.getVehicleListID(vehicle_object.name))

			wpDLCDebug("ai damage taken: "..ai_damaged.." ai damage dealt: "..ai_damage_dealt, false, false)
			if vehicle_object.role ~= "scout" then -- makes sure the vehicle isnt a scout vehicle
				if ai_damaged * 0.3333 < ai_damage_dealt then -- if the ai did more damage than the damage it took / 3
					local ai_reward_ratio = ai_damage_dealt//(ai_damaged * 0.3333)
					sm.train(
						REWARD, 
						vehicle_role, math.clamp(ai_reward_ratio, 1, 2),
						vehicle_object.ai_type, math.clamp(ai_reward_ratio, 1, 3), 
						vehicle_object.strategy, math.clamp(ai_reward_ratio, 1, 2), 
						constructable_vehicle_id, math.clamp(ai_reward_ratio, 1, 3)
					)
				else -- if the ai did less damage than the damage it took / 3
					local ai_punish_ratio = (ai_damaged * 0.3333)//ai_damage_dealt
					sm.train(
						PUNISH, 
						vehicle_role, math.clamp(ai_punish_ratio, 1, 2),
						vehicle_object.ai_type, math.clamp(ai_punish_ratio, 1, 3),
						vehicle_object.strategy, math.clamp(ai_punish_ratio, 1, 2),
						constructable_vehicle_id, math.clamp(ai_punish_ratio, 1, 3)
					)
				end
			else -- if it is a scout vehicle, we instead want to reset its progress on whatever island it was on
				target_island, origin_island = getObjectiveIsland(true)
				g_savedata.ai_knowledge.scout[target_island.name].scouted = 0
				target_island.is_scouting = false
			end
		end

		if not instant and delete ~= true then
			local fire_id = vehicle_object.fire_id
			if fire_id ~= nil then
				wpDLCDebug("explosion fire enabled", true, false)
				s.setFireData(fire_id, true, true)
			end
		end

		s.despawnVehicle(vehicle_id, instant)

		for _, survivor in pairs(vehicle_object.survivors) do
			s.despawnObject(survivor.id, instant)
		end

		if vehicle_object.fire_id ~= nil then
			s.despawnObject(vehicle_object.fire_id, instant)
		end

		if instant == true and delete ~= true then
			local explosion_size = 2
			if vehicle_object.size == "small" then
				explosion_size = 0.5
			elseif vehicle_object.size == "medium" then
				explosion_size = 1
			end

			wpDLCDebug("explosion spawned", true, false)

			s.spawnExplosion(vehicle_object.transform, explosion_size)
		end
	end
end

function tickSquadrons()
	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		if isTickID(squad_index, 60) then
			-- clean out-of-action vehicles
			for vehicle_id, vehicle_object in pairs(squad.vehicles) do

				if vehicle_object.is_killed and vehicle_object.death_timer ~= nil then
					vehicle_object.death_timer = vehicle_object.death_timer + 1
					if vehicle_object.death_timer >= 300 then
						killVehicle(squad_index, vehicle_id, true)
					end
				end

				-- if pilot is incapacitated
				local c = s.getCharacterData(vehicle_object.survivors[1].id)
				if c ~= nil then
					if c.incapacitated or c.dead then
						killVehicle(squad_index, vehicle_id, false)
					end
				end
			end

			-- check if a vehicle needs resupply, removing from current squad and adding to the resupply squad
			if squad_index ~= RESUPPLY_SQUAD_INDEX then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if isVehicleNeedsResupply(vehicle_id) then
						if vehicle_object.ai_type == AI_TYPE_TURRET then
							reload(vehicle_id)
						else
							g_savedata.ai_army.squadrons[RESUPPLY_SQUAD_INDEX].vehicles[vehicle_id] = g_savedata.ai_army.squadrons[squad_index].vehicles[vehicle_id]
							g_savedata.ai_army.squadrons[squad_index].vehicles[vehicle_id] = nil

							wpDLCDebug(vehicle_id.." leaving squad "..squad_index.." to resupply", true, false)

							if tableLength(g_savedata.ai_army.squadrons[squad_index].vehicles) <= 0 then -- squad has no more vehicles
								g_savedata.ai_army.squadrons[squad_index] = nil
	
								for island_index, island in pairs(g_savedata.controllable_islands) do
									if island.assigned_squad_index == squad_index then
										island.assigned_squad_index = -1
									end
								end
							end

							squadInitVehicleCommand(squad, vehicle_object)
						end
					end
					-- check if the vehicle simply needs to reload a machine gun
					local mg_info = isVehicleNeedsReloadMG(vehicle_id)
					if mg_info[1] and mg_info[2] ~= 0 then
						local i = 1
						local successed = false
						local ammoData = {}
						repeat
							local ammo, success = s.getVehicleWeapon(vehicle_id, "Ammo "..mg_info[2].." - "..i)
							if success then
								if ammo.ammo > 0 then
									successed = success
									ammoData[i] = ammo
								end
							end
							i = i + 1
						until (not success)
						if successed then
							s.setVehicleWeapon(vehicle_id, "Ammo "..mg_info[2].." - "..#ammoData, 0)
							s.setVehicleWeapon(vehicle_id, "Ammo "..mg_info[2], ammoData[#ammoData].capacity)
						end
					end
				end
			else
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if (vehicle_object.state.is_simulating and isVehicleNeedsResupply(vehicle_id) == false) or (vehicle_object.state.is_simulating == false and vehicle_object.is_resupply_on_load) then
	
						-- add to new squad
						g_savedata.ai_army.squadrons[RESUPPLY_SQUAD_INDEX].vehicles[vehicle_id] = nil
						addToSquadron(vehicle_object)

						wpDLCDebug(vehicle_id.." resupplied. joining squad", true, false)
					end
				end
			end

			-- tick behaivour / exit conditions
			if squad.command == COMMAND_PATROL then
				local squad_leader_id, squad_leader = getSquadLeader(squad)
				if squad_leader ~= nil then
					if squad_leader.state.s ~= VEHICLE_STATE_PATHING then -- has finished patrol
						setSquadCommand(squad, COMMAND_NONE)
					end
				else
					wpDLCDebug("patrol squad missing leader", true, false)
					setSquadCommand(squad, COMMAND_NONE)
				end
			elseif squad.command == COMMAND_STAGE then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if vehicle_object.ai_type == AI_TYPE_BOAT and vehicle_object.state.s == VEHICLE_STATE_HOLDING then
						squadInitVehicleCommand(squad, vehicle_object)
					end
				end
			elseif squad.command == COMMAND_ATTACK then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if vehicle_object.ai_type == AI_TYPE_BOAT and vehicle_object.state.s == VEHICLE_STATE_HOLDING then
						squadInitVehicleCommand(squad, vehicle_object)
					end
				end
			elseif squad.command == COMMAND_DEFEND then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if vehicle_object.ai_type == AI_TYPE_BOAT and vehicle_object.state.s == VEHICLE_STATE_HOLDING then
						squadInitVehicleCommand(squad, vehicle_object)
					end
				end

				if squad.target_island == nil then
					setSquadCommand(squad, COMMAND_NONE)
				elseif squad.target_island.faction ~= FACTION_AI then
					setSquadCommand(squad, COMMAND_NONE)
				end
			elseif squad.command == COMMAND_RESUPPLY then

				g_savedata.ai_army.squadrons[RESUPPLY_SQUAD_INDEX].target_island = nil
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if #vehicle_object.path == 0 then
						wpDLCDebug("resupply mission recalculating target island for: "..vehicle_id, true, false)
						local ally_island = getResupplyIsland(vehicle_object.transform)
						resetPath(vehicle_object)
						wpDLCDebugVehicle(vehicle_id, "(vehicle resupplying) Vehicle: "..vehicle_id.." is resupplying! path reset!", true, false)
						addPath(vehicle_object, m.multiply(ally_island.transform, m.translation(math.random(-250, 250), CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), math.random(-250, 250))))
					end
					
					if m.distance(g_savedata.ai_base_island.transform, vehicle_object.transform) < RESUPPLY_RADIUS then

						if vehicle_object.state.is_simulating then
							-- resupply ammo
							reload(vehicle_id)
						else
							s.resetVehicleState(vehicle_id)
							vehicle_object.is_resupply_on_load = true
						end
					end

					for island_index, island in pairs(g_savedata.controllable_islands) do
						if island.faction == FACTION_AI then
							if m.distance(island.transform, vehicle_object.transform) < CAPTURE_RADIUS then

								if vehicle_object.state.is_simulating then
									-- resupply ammo
									reload(vehicle_id)
								else
									s.resetVehicleState(vehicle_id)
									vehicle_object.is_resupply_on_load = true
								end
							end
						end
					end
				end

			elseif squad.command == COMMAND_INVESTIGATE then
				-- head to search area

				if squad.investigate_transform then
					local is_all_vehicles_at_search_area = true

					for vehicle_id, vehicle_object in pairs(squad.vehicles) do
						if vehicle_object.state.s ~= VEHICLE_STATE_HOLDING then
							is_all_vehicles_at_search_area = false
						end
					end

					if is_all_vehicles_at_search_area then
						squad.investigate_transform = nil
					end
				else
					setSquadCommand(squad, COMMAND_NONE)
				end
			elseif squad.command == COMMAND_ENGAGE then
				local squad_vision = squadGetVisionData(squad)
				local player_counts = {}
				local vehicle_counts = {}
				local function incrementCount(t, index) t[index] = t[index] and t[index] + 1 or 1 end
				local function decrementCount(t, index) t[index] = t[index] and t[index] - 1 or 0 end
				local function getCount(t, index) return t[index] or 0 end

				local function retargetVehicle(vehicle_object, target_player_id, target_vehicle_id)
					-- decrement previous target count
					if vehicle_object.target_player_id ~= -1 then decrementCount(player_counts, vehicle_object.target_player_id)
					elseif vehicle_object.target_vehicle_id ~= -1 then decrementCount(vehicle_counts, vehicle_object.target_vehicle_id) end

					vehicle_object.target_player_id = target_player_id
					vehicle_object.target_vehicle_id = target_vehicle_id

					-- increment new target count
					if vehicle_object.target_player_id ~= -1 then incrementCount(player_counts, vehicle_object.target_player_id)
					elseif vehicle_object.target_vehicle_id ~= -1 then incrementCount(vehicle_counts, vehicle_object.target_vehicle_id) end
				end

				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					-- check existing target is still visible

					if vehicle_object.target_player_id ~= -1 and squad_vision:isPlayerVisible(vehicle_object.target_player_id) == false then
						vehicle_object.target_player_id = -1
					elseif vehicle_object.target_vehicle_id ~= -1 and squad_vision:isVehicleVisible(vehicle_object.target_vehicle_id) == false then
						vehicle_object.target_vehicle_id = -1
					end

					-- find targets if not targeting anything

					if vehicle_object.target_player_id == -1 and vehicle_object.target_vehicle_id == -1 then
						if #squad_vision.visible_players > 0 then
							vehicle_object.target_player_id = squad_vision:getBestTargetPlayerID()
							incrementCount(player_counts, vehicle_object.target_player_id)
						elseif #squad_vision.visible_vehicles > 0 then
							vehicle_object.target_vehicle_id = squad_vision:getBestTargetVehicleID()
							incrementCount(vehicle_counts, vehicle_object.target_vehicle_id)
						end
					else
						if vehicle_object.target_player_id ~= -1 then
							incrementCount(player_counts, vehicle_object.target_player_id)
						elseif vehicle_object.target_vehicle_id ~= -1 then
							incrementCount(vehicle_counts, vehicle_object.target_vehicle_id)
						end
					end
				end

				local squad_vehicle_count = #squad.vehicles
				local visible_target_count = #squad_vision.visible_players + #squad_vision.visible_vehicles
				local vehicles_per_target = math.max(math.floor(squad_vehicle_count / visible_target_count), 1)

				local function isRetarget(target_player_id, target_vehicle_id)
					return (target_player_id == -1 and target_vehicle_id == -1) 
						or (target_player_id ~= -1 and getCount(player_counts, target_player_id) > vehicles_per_target)
						or (target_vehicle_id ~= -1 and getCount(vehicle_counts, target_vehicle_id) > vehicles_per_target)
				end

				-- find vehicles to retarget to visible players

				for visible_player_id, visible_player in pairs(squad_vision.visible_players_map) do
					if getCount(player_counts, visible_player_id) < vehicles_per_target then
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							if isRetarget(vehicle_object.target_player_id, vehicle_object.target_vehicle_id) then
								retargetVehicle(vehicle_object, visible_player_id, -1)
								break
							end
						end
					end
				end

				-- find vehicles to retarget to visible vehicles

				for visible_vehicle_id, visible_vehicle in pairs(squad_vision.visible_vehicles_map) do
					if getCount(vehicle_counts, visible_vehicle_id) < vehicles_per_target then
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							if isRetarget(vehicle_object.target_player_id, vehicle_object.target_vehicle_id) then
								retargetVehicle(vehicle_object, -1, visible_vehicle_id)
								break
							end
						end
					end
				end

				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					-- update waypoint and target data

					if vehicle_object.target_player_id ~= -1 then
						local target_player_id = vehicle_object.target_player_id
						local target_player_data = squad_vision.visible_players_map[target_player_id]
						local target_player = target_player_data.obj
						local target_x, target_y, target_z = m.position(target_player.last_known_pos)
						local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_object.transform)
						

						if #vehicle_object.path <= 1 then
							resetPath(vehicle_object)

							if vehicle_object.ai_type == AI_TYPE_PLANE then

								if xzDistance(target_player.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) > 700 then
									addPath(vehicle_object, m.multiply(target_player.last_known_pos, m.translation(target_player.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 75), target_player.last_known_pos)))
									vehicle_object.is_strafing = true
								elseif xzDistance(target_player.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) > 150 and vehicle_object.is_strafing ~= true then
									addPath(vehicle_object, m.multiply(target_player.last_known_pos, m.translation(target_player.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 75, 200), target_player.last_known_pos)))
								elseif xzDistance(target_player.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) < 250 then
									addPath(vehicle_object, m.multiply(target_player.last_known_pos, m.translation(target_player.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 15, 50), target_player.last_known_pos)))
									vehicle_object.is_strafing = false
								else
									addPath(vehicle_object, m.multiply(target_player.last_known_pos, m.translation(target_player.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 75), target_player.last_known_pos))) 
								end
							elseif vehicle_object.ai_type ~= AI_TYPE_LAND then
								addPath(vehicle_object, m.multiply(target_player.last_known_pos, m.translation(target_player.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 75), target_player.last_known_pos)))
							end
						end

						for i, char in pairs(vehicle_object.survivors) do
							s.setAITargetCharacter(char.id, vehicle_object.target_player_id)

							if i ~= 1 or vehicle_object.ai_type == AI_TYPE_TURRET then
								s.setAIState(char.id, 1)
							end
						end
					elseif vehicle_object.target_vehicle_id ~= -1 then
						local target_vehicle = squad_vision.visible_vehicles_map[vehicle_object.target_vehicle_id].obj
						local target_x, target_y, target_z = m.position(target_vehicle.last_known_pos)
						local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_object.transform)

						
						if #vehicle_object.path <= 1 then
							resetPath(vehicle_object)
							if vehicle_object.type == AI_TYPE_PLANE then
								if m.distance(target_vehicle.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) > 700 then
									addPath(vehicle_object, m.multiply(target_vehicle.last_known_pos, m.translation(target_vehicle.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 50), target_vehicle.last_known_pos)))
									vehicle_object.is_strafing = true
								elseif m.distance(target_vehicle.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) > 150 and vehicle_object.is_strafing ~= true then
									addPath(vehicle_object, m.multiply(target_vehicle.last_known_pos, m.translation(target_vehicle.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 75, 100), target_vehicle.last_known_pos)))
								elseif m.distance(target_vehicle.last_known_pos, vehicle_object.transform) - math.abs(target_y - vehicle_y) < 250 then
									addPath(vehicle_object, m.multiply(target_vehicle.last_known_pos, m.translation(target_vehicle.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 15, 25), target_vehicle.last_known_pos)))
									vehicle_object.is_strafing = false
								else
									addPath(vehicle_object, m.multiply(target_vehicle.last_known_pos, m.translation(target_vehicle.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 50), target_vehicle.last_known_pos)))
								end
							elseif vehicle_object.ai_type ~= AI_TYPE_LAND then
								addPath(vehicle_object, m.multiply(target_vehicle.last_known_pos, m.translation(target_vehicle.last_known_pos, target_y + math.max(target_y + (vehicle_object.id % 5) + 25, 50), target_vehicle.last_known_pos)))
							end
						end
						for i, char in pairs(vehicle_object.survivors) do
							s.setAITargetVehicle(char.id, vehicle_object.target_vehicle_id)

							if i ~= 1 or vehicle_object.ai_type == AI_TYPE_TURRET then
								s.setAIState(char.id, 1)
							end
						end
					end
				end

				if squad_vision:is_engage() == false then
					setSquadCommand(squad, COMMAND_NONE)
				end
			end
			if squad.command ~= COMMAND_RETREAT then
				for vehicle_id, vehicle_object in pairs(squad.vehicles) do
					if vehicle_object.target_player_id ~= -1 or vehicle_object.target_vehicle_id ~= -1 then
						if vehicle_object.capabilities.gps_missiles then setKeypadTargetCoords(vehicle_id, vehicle_object, squad) end
					end
				end
			end
		end
	end
end

function tickVisionRadius()

	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if isTickID(vehicle_id, 240) then
				local vehicle_transform = vehicle_object.transform
				local weather = s.getWeather(vehicle_transform)
				local clock = s.getTime()
				if vehicle_object.vision.is_radar then
					vehicle_object.vision.radius = vehicle_object.vision.base_radius * (1 - (weather.fog * 0.2)) * (0.6 + (clock.daylight_factor * 0.2)) * (1 - (weather.rain * 0.2))
				else
					vehicle_object.vision.radius = vehicle_object.vision.base_radius * (1 - (weather.fog * 0.6)) * (0.2 + (clock.daylight_factor * 0.6)) * (1 - (weather.rain * 0.6))
				end
			end
		end
	end
end

function tickVision()

	-- analyse player vehicles
	for player_vehicle_id, player_vehicle in pairs(g_savedata.player_vehicles) do
		if isTickID(player_vehicle_id, 30) then
			local player_vehicle_transform = player_vehicle.transform

			for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
				if squad_index ~= RESUPPLY_SQUAD_INDEX then
					-- reset target visibility state to investigate

					if squad.target_vehicles[player_vehicle_id] ~= nil then
						if player_vehicle.death_pos == nil then
							squad.target_vehicles[player_vehicle_id].state = TARGET_VISIBILITY_INVESTIGATE
						else
							squad.target_vehicles[player_vehicle_id] = nil
						end
					end

					-- check if target is visible to any vehicles
					for vehicle_id, vehicle_object in pairs(squad.vehicles) do
						local vehicle_transform = vehicle_object.transform

						if vehicle_transform ~= nil and player_vehicle_transform ~= nil then
							local distance = m.distance(player_vehicle_transform, vehicle_transform)

							local local_vision_radius = vehicle_object.vision.radius

							-- radar and sonar adjustments
							if player_vehicle_transform[14] >= -1 and vehicle_object.vision.is_radar then
								local_vision_radius = local_vision_radius * 3
							end

							if player_vehicle_transform[14] < -1 and vehicle_object.vision.is_sonar == false then
								local_vision_radius = local_vision_radius * 0.4
							end
							
							if distance < local_vision_radius and player_vehicle.death_pos == nil then
								if squad.target_vehicles[player_vehicle_id] == nil then
									squad.target_vehicles[player_vehicle_id] = {
										state = TARGET_VISIBILITY_VISIBLE,
										last_known_pos = player_vehicle_transform,
									}
								else
									local target_vehicle = squad.target_vehicles[player_vehicle_id]
									target_vehicle.state = TARGET_VISIBILITY_VISIBLE
									target_vehicle.last_known_pos = player_vehicle_transform
								end

								break
							end
						end
					end
				end
			end

			if player_vehicle.death_pos ~= nil then
				if m.distance(player_vehicle.death_pos, player_vehicle_transform) > 500 then
					local player_vehicle_data = s.getVehicleData(player_vehicle_id)
					player_vehicle.death_pos = nil
					player_vehicle.damage_threshold = player_vehicle.damage_threshold + player_vehicle_data.voxels / 10
				end
			end

			if render_debug then
				local debug_data = ""

				debug_data = debug_data .. "\ndamage: " .. player_vehicle.current_damage
				debug_data = debug_data .. "\nthreshold: " .. player_vehicle.damage_threshold

				if recent_spotter ~= nil then debug_data = debug_data .. "\nspotter: " .. player_vehicle.recent_spotter end
				if last_known_pos ~= nil then debug_data = debug_data .. "last_known_pos: " end
				if death_pos ~= nil then debug_data = debug_data .. "death_pos: " end
				for player_debugging_id, v in pairs(playerData.isDebugging) do
					if playerData.isDebugging[player_debugging_id] then
						s.removeMapObject(player_debugging_id, player_vehicle.map_id)
						s.addMapObject(player_debugging_id, player_vehicle.map_id, 1, 4, 0, 150, 0, 150, player_vehicle_id, 0, "Tracked Vehicle: " .. player_vehicle_id, 1, debug_data, 0, 0, 255, 255)
					end
				end
			end
		end
	end

	-- analyse players
	local playerList = s.getPlayers()
	for player_id, player in pairs(playerList) do
		if isTickID(player_id, 30) then
			if player.object_id then
				local player_transform = s.getPlayerPos(player.id)
				
				for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
					if squad_index ~= RESUPPLY_SQUAD_INDEX then
						-- reset target visibility state to investigate

						if squad.target_players[player.object_id] ~= nil then
							squad.target_players[player.object_id].state = TARGET_VISIBILITY_INVESTIGATE
						end

						-- check if target is visible to any vehicles

						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							local vehicle_transform = vehicle_object.transform
							local distance = m.distance(player_transform, vehicle_transform)

							if distance < vehicle_object.vision.radius then
								g_savedata.ai_knowledge.last_seen_positions[player.steam_id] = player_transform
								if squad.target_players[player.object_id] == nil then
									squad.target_players[player.object_id] = {
										state = TARGET_VISIBILITY_VISIBLE,
										last_known_pos = player_transform,
									}
								else
									local target_player = squad.target_players[player.object_id]
									target_player.state = TARGET_VISIBILITY_VISIBLE
									target_player.last_known_pos = player_transform
								end
								
								break
							end
						end
					end
				end
			end
		end
	end
end

function tickVehicles()
	local vehicle_update_tickrate = 30
	if isTickID(0, 60) then
		debug_mode_blinker = not debug_mode_blinker
	end

	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if isTickID(vehicle_id, vehicle_update_tickrate) then

				-- scout vehicles
				if vehicle_object.role == "scout" then
					local target_island, origin_island = getObjectiveIsland(true)
					if g_savedata.ai_knowledge.scout[target_island.name].scouted < scout_requirement then
						if #vehicle_object.path == 0 then -- if its finishing circling the island
							setSquadCommandScout(squad)
						end
						local target_island, origin_island = getObjectiveIsland(true)
						if xzDistance(vehicle_object.transform, target_island.transform) <= vehicle_object.vision.radius then
							if target_island.faction == FACTION_NEUTRAL then
								g_savedata.ai_knowledge.scout[target_island.name].scouted = math.clamp(g_savedata.ai_knowledge.scout[target_island.name].scouted + vehicle_update_tickrate * 4, 0, scout_requirement)
							else
								g_savedata.ai_knowledge.scout[target_island.name].scouted = math.clamp(g_savedata.ai_knowledge.scout[target_island.name].scouted + vehicle_update_tickrate, 0, scout_requirement)
							end
						end
					end
				end

				local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_object.transform)
				if vehicle_y <= BOAT_EXPLOSION_DEPTH and vehicle_object.ai_type == AI_TYPE_BOAT or vehicle_y <= HELI_EXPLOSION_DEPTH and vehicle_object.ai_type == AI_TYPE_HELI or vehicle_y <= PLANE_EXPLOSION_DEPTH and vehicle_object.ai_type == AI_TYPE_PLANE then
					killVehicle(squad_index, vehicle_id, true)
				end
				local ai_target = nil
				if ai_state ~= 2 then ai_state = 1 end
				local ai_speed_pseudo = AI_SPEED_PSEUDO_BOAT * vehicle_update_tickrate / 60

				if(vehicle_object.ai_type ~= AI_TYPE_TURRET) then

					if vehicle_object.state.s == VEHICLE_STATE_PATHING then

						if vehicle_object.ai_type == AI_TYPE_PLANE then
							ai_speed_pseudo = AI_SPEED_PSEUDO_PLANE * vehicle_update_tickrate / 60
						elseif vehicle_object.ai_type == AI_TYPE_HELI then
							ai_speed_pseudo = AI_SPEED_PSEUDO_HELI * vehicle_update_tickrate / 60
						elseif vehicle_object.ai_type == AI_TYPE_LAND then
							vehicle_object.terrain_type = "offroad"
							vehicle_object.is_aggressive = "normal"

							if squad.command == COMMAND_ENGAGE or squad.command == COMMAND_RESUPPLY or squad.command == COMMAND_STAGE then
								vehicle_object.is_aggressive = "aggressive"
							end

							if s.isInZone(vehicle_object.transform, "land_ai_road") then
								vehicle_object.terrain_type = "road"
							elseif s.isInZone(vehicle_object.transform, "land_ai_bridge") then
								vehicle_object.terrain_type = "bridge"
							end

							ai_speed_pseudo = (vehicle_object.speed[vehicle_object.is_aggressive][vehicle_object.terrain_type] or AI_SPEED_PSEUDO_LAND) * vehicle_update_tickrate / 60
						else
							ai_speed_pseudo = AI_SPEED_PSEUDO_BOAT * vehicle_update_tickrate / 60
						end

						if #vehicle_object.path == 0 then
							vehicle_object.state.s = VEHICLE_STATE_HOLDING
						else
							if ai_state ~= 2 then ai_state = 1 end
							if vehicle_object.ai_type ~= AI_TYPE_LAND then 
								ai_target = m.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z)
							else
								local veh_x, veh_y, veh_z = m.position(vehicle_object.transform)
								ai_target = m.translation(vehicle_object.path[1].x, veh_y, vehicle_object.path[1].z)
								setLandTarget(vehicle_id, vehicle_object)
							end
							if vehicle_object.ai_type == AI_TYPE_BOAT then ai_target[14] = 0 end
	
							local vehicle_pos = vehicle_object.transform
							local distance = m.distance(ai_target, vehicle_pos)
	
							if vehicle_object.ai_type == AI_TYPE_PLANE and distance < WAYPOINT_CONSUME_DISTANCE * 4 and vehicle_object.role == "scout" or distance < WAYPOINT_CONSUME_DISTANCE and vehicle_object.ai_type == AI_TYPE_PLANE or distance < WAYPOINT_CONSUME_DISTANCE and vehicle_object.ai_type == AI_TYPE_HELI or vehicle_object.ai_type == AI_TYPE_LAND and distance < 7 then
								if #vehicle_object.path > 1 then
									s.removeMapID(0, vehicle_object.path[1].ui_id)
									table.remove(vehicle_object.path, 1)
									if vehicle_object.ai_type == AI_TYPE_LAND then
										setLandTarget(vehicle_id, vehicle_object)
									end
								elseif vehicle_object.role == "scout" then
									resetPath(vehicle_object)
									target_island, origin_island = getObjectiveIsland(true)
									if target_island then
										local holding_route = g_holding_pattern
										addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[1].x, CRUISE_HEIGHT * 2, holding_route[1].z)))
										addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[2].x, CRUISE_HEIGHT * 2, holding_route[2].z)))
										addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[3].x, CRUISE_HEIGHT * 2, holding_route[3].z)))
										addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[4].x, CRUISE_HEIGHT * 2, holding_route[4].z)))
									end
								elseif vehicle_object.ai_type ~= AI_TYPE_LAND then
									-- if we have reached last waypoint start holding there
									wpDLCDebug("set plane "..vehicle_id.." to holding", true, false)
									vehicle_object.state.s = VEHICLE_STATE_HOLDING
								end
							elseif vehicle_object.ai_type == AI_TYPE_BOAT and distance < WAYPOINT_CONSUME_DISTANCE then
								if #vehicle_object.path > 0 then
									s.removeMapID(0, vehicle_object.path[1].ui_id)
									table.remove(vehicle_object.path, 1)
								else
									-- if we have reached last waypoint start holding there
									wpDLCDebug("set boat "..vehicle_id.." to holding", true, false)
									vehicle_object.state.s = VEHICLE_STATE_HOLDING
								end
							end
						end

						if squad.command == COMMAND_ENGAGE and vehicle_object.ai_type == AI_TYPE_HELI then
							ai_state = 3
						end

						refuel(vehicle_id)
					elseif vehicle_object.state.s == VEHICLE_STATE_HOLDING then

						ai_speed_pseudo = AI_SPEED_PSEUDO_PLANE * vehicle_update_tickrate / 60

						if vehicle_object.ai_type == AI_TYPE_BOAT then
							ai_state = 0
						elseif vehicle_object.ai_type == AI_TYPE_LAND then
							local target = nil
							local squad_vision = squadGetVisionData(squad)
							if vehicle_object.target_vehicle_id ~= -1 and vehicle_object.target_vehicle_id and squad_vision.visible_vehicles_map[vehicle_object.target_vehicle_id] then
								target = squad_vision.visible_vehicles_map[vehicle_object.target_vehicle_id].obj
							elseif vehicle_object.target_player_id ~= -1 and vehicle_object.target_player_id and squad_vision.visible_players_map[vehicle_object.target_player_id] then
								target = squad_vision.visible_players_map[vehicle_object.target_player_id].obj
							end
							if target and m.distance(m.translation(0, 0, 0), target.last_known_pos) > 5 then
								ai_target = target.last_known_pos
								local distance = m.distance(vehicle_object.transform, ai_target)
								local possiblePaths = s.pathfindOcean(vehicle_object.transform, ai_target)
								local is_better_pos = false
								for path_index, path in pairs(possiblePaths) do
									if m.distance(matrix.translation(path.x, path.y, path.z), ai_target) < distance then
										is_better_pos = true
									end
								end
								if is_better_pos then
									addPath(vehicle_object, ai_target)
								else
									ai_state = 0
								end
							else
								ai_state = 0
							end
						else
							if #vehicle_object.path == 0 then
								wpDLCDebugVehicle(vehicle_id, "Vehicle: "..vehicle_id.." has 0 paths, adding more", true, false)
								addPath(vehicle_object, vehicle_object.transform)
							end

							ai_state = 1
							ai_target = m.translation(vehicle_object.path[1].x + g_holding_pattern[vehicle_object.holding_index].x, vehicle_object.path[1].y, vehicle_object.path[1].z + g_holding_pattern[vehicle_object.holding_index].z)

							local vehicle_pos = vehicle_object.transform
							local distance = m.distance(ai_target, vehicle_pos)

							if distance < WAYPOINT_CONSUME_DISTANCE and vehicle_object.ai_type ~= AI_TYPE_LAND or distance < 7 and vehicle_object.ai_type == AI_TYPE_LAND then
								vehicle_object.holding_index = 1 + ((vehicle_object.holding_index) % 4);
							end
						end
					end

					--set ai behaviour
					if ai_target ~= nil then
						if vehicle_object.state.is_simulating then
							s.setAITarget(vehicle_object.survivors[1].id, ai_target)
							s.setAIState(vehicle_object.survivors[1].id, ai_state)
						else
							local ts_x, ts_y, ts_z = m.position(ai_target)
							local vehicle_pos = vehicle_object.transform
							local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_pos)
							local movement_x = ts_x - vehicle_x
							local movement_y = ts_y - vehicle_y
							local movement_z = ts_z - vehicle_z
							local length_xz = math.sqrt((movement_x * movement_x) + (movement_z * movement_z))

							local function clamp(value, min, max)
								return math.min(max, math.max(min, value))
							end

							local speed_pseudo = ai_speed_pseudo * g_debug_speed_multiplier
							movement_x = clamp(movement_x * speed_pseudo / length_xz, -math.abs(movement_x), math.abs(movement_x))
							movement_y = math.min(speed_pseudo, math.max(movement_y, -speed_pseudo))
							movement_z = clamp(movement_z * speed_pseudo / length_xz, -math.abs(movement_z), math.abs(movement_z))

							local rotation_matrix = m.rotationToFaceXZ(movement_x, movement_z)
							local new_pos = m.multiply(m.translation(vehicle_x + movement_x, vehicle_y + movement_y, vehicle_z + movement_z), rotation_matrix)

							if s.getVehicleLocal(vehicle_id) == false then
								s.setVehiclePos(vehicle_id, new_pos)

								for npc_index, npc_object in pairs(vehicle_object.survivors) do
									s.setObjectPos(npc_object.id, new_pos)
								end

								if vehicle_object.fire_id ~= nil then
									s.setObjectPos(vehicle_object.fire_id, new_pos)
								end
							end
						end
					end
				end
				if render_debug then
					local vehicle_pos = vehicle_object.transform
					local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_pos)

					local debug_data = vehicle_object.state.s .. "\n"
					debug_data = debug_data .. "Waypoints: " .. #vehicle_object.path .."\n\n"

					debug_data = debug_data .. "Squad: " .. squad_index .."\n"
					debug_data = debug_data .. "Comm: " .. squad.command .."\n"
					debug_data = debug_data .. "AI State: ".. ai_state .. "\n"
					if squad.target_island then debug_data = debug_data .. "\n" .. "ISLE: " .. squad.target_island.name .. "\n" end

					debug_data = debug_data .. "TP: " .. vehicle_object.target_player_id .."\n"
					debug_data = debug_data .. "TV: " .. vehicle_object.target_vehicle_id .."\n\n"

					if squad_index ~= RESUPPLY_SQUAD_INDEX then
						local squad_vision = squadGetVisionData(squad)
						debug_data = debug_data .. "squad visible players: " .. #squad_vision.visible_players .."\n"
						debug_data = debug_data .. "squad visible vehicles: " .. #squad_vision.visible_vehicles .."\n"
						debug_data = debug_data .. "squad investigate players: " .. #squad_vision.investigate_players .."\n"
						debug_data = debug_data .. "squad investigate vehicles: " .. #squad_vision.investigate_vehicles .."\n\n"
					end

					local hp = g_savedata.settings.ENEMY_HP
					if vehicle_object.size == "large" then
						hp = hp * 4
					elseif vehicle_object.size == "medium" then
						hp = hp * 2
					end
					if g_savedata.settings.SINKING_MODE or vehicle_object.capabilities.gps_missiles then
						hp = hp * 8
					end
					debug_data = debug_data .. "hp: " .. vehicle_object.current_damage .. " / " .. hp .. "\n"

					debug_data = debug_data .. "Pos: [" .. math.floor(vehicle_x) .. " ".. math.floor(vehicle_y) .. " ".. math.floor(vehicle_z) .. "]\n"
					if ai_target then
						local ts_x, ts_y, ts_z = m.position(ai_target)
						debug_data = debug_data .. "Dest: [" .. math.floor(ts_x) .. " ".. math.floor(ts_y) .. " ".. math.floor(ts_z) .. "]\n"

						local dist_to_dest = math.sqrt((ts_x - vehicle_x) ^ 2 + (ts_z - vehicle_z) ^ 2)
						debug_data = debug_data .. "Dist: " .. math.floor(dist_to_dest) .. "m\n"
					end

					if vehicle_object.state.is_simulating then
						debug_data = debug_data .. "\n\nSIMULATING\n"
						debug_data = debug_data .. "needs resupply: " .. tostring(isVehicleNeedsResupply(vehicle_id)) .. "\n"
					else
						debug_data = debug_data .. "\n\nPSEUDO\n"
						debug_data = debug_data .. "resupply on load: " .. tostring(vehicle_object.is_resupply_on_load) .. "\n"
					end

					local state_icons = {
						[COMMAND_ATTACK] = 18,
						[COMMAND_STAGE] = 2,
						[COMMAND_ENGAGE] = 5,
						[COMMAND_DEFEND] = 19,
						[COMMAND_PATROL] = 15,
						[COMMAND_TURRET] = 14,
						[COMMAND_RESUPPLY] = 11,
						[COMMAND_SCOUT] = 4,
					}
					local r = 55
					local g = 0
					local b = 200
					local vehicle_icon = debug_mode_blinker and 16 or state_icons[squad.command]
					if vehicle_object.ai_type == AI_TYPE_LAND then
						g = 255
						b = 125
						vehicle_icon = debug_mode_blinker and 12 or state_icons[squad.command]
					elseif vehicle_object.ai_type == AI_TYPE_HELI then
						r = 255
						b = 200
						vehicle_icon = debug_mode_blinker and 15 or state_icons[squad.command]
					elseif vehicle_object.ai_type == AI_TYPE_PLANE then
						g = 200
						vehicle_icon = debug_mode_blinker and 13 or state_icons[squad.command]
					elseif vehicle_object.ai_type == AI_TYPE_TURRET then
						r = 131
						g = 101
						b = 57
						vehicle_icon = debug_mode_blinker and 14 or state_icons[squad.command]
					end
					for player_debugging_id, v in pairs(playerData.isDebugging) do
						if playerData.isDebugging[player_debugging_id] then
							s.removeMapObject(player_debugging_id ,vehicle_object.map_id)
							s.addMapObject(player_debugging_id, vehicle_object.map_id, 1, vehicle_icon or 3, 0, 0, 0, 0, vehicle_id, 0, "AI " .. vehicle_object.ai_type .. " " .. vehicle_id.."\n"..vehicle_object.name, vehicle_object.vision.radius, debug_data, r, g, b, 255)

							local is_render = tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0)

							if(#vehicle_object.path >= 1) then
								s.removeMapLine(player_debugging_id, vehicle_object.map_id)

								s.addMapLine(player_debugging_id, vehicle_object.map_id, vehicle_pos, m.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z), 0.5, r, g, b, 255)

								for i = 1, #vehicle_object.path - 1 do
									local waypoint = vehicle_object.path[i]
									local waypoint_next = vehicle_object.path[i + 1]

									local waypoint_pos = m.translation(waypoint.x, waypoint.y, waypoint.z)
									local waypoint_pos_next = m.translation(waypoint_next.x, waypoint_next.y, waypoint_next.z)

									s.removeMapLine(player_debugging_id, waypoint.ui_id)

									if is_render then
										s.addMapLine(player_debugging_id, waypoint.ui_id, waypoint_pos, waypoint_pos_next, 0.5, r, g, b, 255)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

function tickUpdateVehicleData()
	for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			if isTickID(vehicle_id, 30) then
				vehicle_object.transform = s.getVehiclePos(vehicle_id)
			end
		end
	end

	for player_vehicle_id, player_vehicle in pairs(g_savedata.player_vehicles) do
		if isTickID(player_vehicle_id, 30) then
			player_vehicle.transform = s.getVehiclePos(player_vehicle_id)
		end
	end
end

function tickTerrainScanners()
	printTable(g_savedata.terrain_scanner_links, true, false)
	for vehicle_id, terrain_scanner in pairs(g_savedata.terrain_scanner_links) do
		local vehicle_data = s.getVehicleData(vehicle_id)
		local terrain_scanner_data = s.getVehicleData(terrain_scanner)
		
		if hasTag(terrain_scanner_data.tags, "from=dlc_weapons_terrain_scanner") then
			wpDLCDebug("terrain scanner loading!", true, false)
			wpDLCDebug("ter id: "..terrain_scanner, true, false)
			wpDLCDebug("veh id: "..vehicle_id, true, false)
			dial_read_attempts = 0
			repeat
				dial_read_attempts = dial_read_attempts + 1
				terrain_height, success = s.getVehicleDial(terrain_scanner, "MEASURED_DISTANCE")
				if success and terrain_height.value ~= 0 then
					printTable(terrain_height, true, false)
					local new_terrain_height = (1000 - terrain_height.value) + 5
					local vehicle_x, vehicle_y, vehicle_z = m.position(vehicle_data.transform)
					local new_vehicle_matrix = m.translation(vehicle_x, new_terrain_height, vehicle_z)
					s.setVehiclePos(vehicle_id, new_vehicle_matrix)
					wpDLCDebug("set land vehicle to new y level!", true, false)
					g_savedata.terrain_scanner_links[vehicle_id] = "Just Teleported"
					s.despawnVehicle(terrain_scanner, true)
				else
					if success then
						wpDLCDebug("Unable to get terrain height checker's dial! "..dial_read_attempts.."x (read = 0)", true, true)
					else
						wpDLCDebug("Unable to get terrain height checker's dial! "..dial_read_attempts.."x (not success)", true, true)
					end
					
				end
				if dial_read_attempts >= 2 then return end
			until(success and terrain_height.value ~= 0)
		end
	end
end

function tickModifiers()
	if isTickID(g_savedata.tick_counter, time.hour / 2) then -- defence, if the player has attacked within the last 30 minutes, increase defence
		if g_savedata.tick_counter - g_savedata.ai_history.has_defended <= time.hour / 2 and g_savedata.ai_history.has_defended ~= 0 then -- if the last time the player attacked was equal or less than 30 minutes ago
			sm.train(REWARD, "defend", 4)
			sm.train(PUNISH, "attack", 3)
			wpDLCDebug("players have attacked within the last 30 minutes! increasing defence, decreasing attack!", true, false)
		end
	end
	if isTickID(g_savedata.tick_counter, time.hour) then -- attack, if the player has not attacked in the last one hour, raise attack
		if g_savedata.tick_counter - g_savedata.ai_history.has_defended > time.hour then -- if the last time the player attacked was more than an hour ago
			sm.train(REWARD, "attack", 3)
			wpDLCDebug("players have not attacked in the past hour! increasing attack!", true, false)
		end
	end
	if isTickID(g_savedata.tick_counter, time.hour * 2) then -- defence, if the player has not attacked in the last two hours, then lower defence
		if g_savedata.tick_counter - g_savedata.ai_history.has_defended > time.hour * 2 then -- if the last time the player attacked was more than two hours ago
			sm.train(PUNISH, "defend", 3)
			wpDLCDebug("players have not attacked in the last two hours! lowering defence!", true, false)
		end
	end

	-- checks if the player is nearby the ai's controlled islands, works like a capacitor, however the
	-- closer the player is, the faster it will charge up, once it hits its limit, it will then detect that the
	-- player is attacking, and will then use that to tell the ai to increase on defence
	for island_index, island in pairs(g_savedata.controllable_islands) do
		if isTickID(island_index * 30, time.minute / 2) then
			if island.faction == FACTION_AI then
				local player_list = s.getPlayers()
				for player_index, player in pairs(player_list) do
					player_pos = s.getPlayerPos(player)
					player_island_dist = xzDistance(player_pos, island.transform)
					if player_island_dist < 1000 then
						g_savedata.ai_history.defended_charge = g_savedata.ai_history.defended_charge + 3
					elseif player_island_dist < 2000 then
						g_savedata.ai_history.defended_charge = g_savedata.ai_history.defended_charge + 2
					elseif player_island_dist < 3000 then
						g_savedata.ai_history.defended_charge = g_savedata.ai_history.defended_charge + 1
					end
					if g_savedata.ai_history.defended_charge >= 6 then
						g_savedata.ai_history.defended_charge = 0
						g_savedata.ai_history.has_defended = g_savedata.tick_counter
						wpDLCDebug(player.name.." has been detected to be attacking "..island.name..", the ai will be raising their defences!", true, false)
					end
				end
			end
		end
	end
end

function onTick(tick_time)
	g_tick_counter = g_tick_counter + 1
	g_savedata.tick_counter = g_savedata.tick_counter + 1

	if is_dlc_weapons then
		tickUpdateVehicleData()
		tickVisionRadius()
		tickVision()
		tickGamemode()
		tickAI()
		tickSquadrons()
		tickVehicles()
		tickModifiers()
		if tableLength(g_savedata.terrain_scanner_links) > 0 then
			tickTerrainScanners()
		end
	end
end

function refuel(vehicle_id)
    s.setVehicleTank(vehicle_id, "Jet 1", 999, 2)
    s.setVehicleTank(vehicle_id, "Jet 2", 999, 2)
    s.setVehicleTank(vehicle_id, "Jet 3", 999, 2)
    s.setVehicleTank(vehicle_id, "Diesel 1", 999, 1)
    s.setVehicleTank(vehicle_id, "Diesel 2", 999, 1)
    s.setVehicleBattery(vehicle_id, "Battery 1", 1)
    s.setVehicleBattery(vehicle_id, "Battery 2", 1)
end

function reload(vehicle_id)
	wpDLCDebug("reloaded: "..vehicle_id, true, false)
	for i=1, 15 do
		s.setVehicleWeapon(vehicle_id, "Ammo "..i, 999)
	end
end

--[[
        Utility Functions
--]]

function build_locations(playlist_index, location_index)
    local location_data = s.getLocationData(playlist_index, location_index)

    local addon_components =
    {
        vehicles = {},
        survivors = {},
        objects = {},
		zones = {},
		fires = {},
    }

    local is_valid_location = false

    for object_index, object_data in iterObjects(playlist_index, location_index) do

        for tag_index, tag_object in pairs(object_data.tags) do

            if tag_object == "from=dlc_weapons" then
                is_valid_location = true
            end
			if tag_object == "from=dlc_weapons_terrain_scanner" then
				if object_data.type == "vehicle" then
					g_savedata.terrain_scanner_prefab = { playlist_index = playlist_index, location_index = location_index, object_index = object_index}
				end
			end
			if tag_object == "from=dlc_weapons_flag" then
				if object_data.type == "vehicle" then
					flag_prefab = { playlist_index = playlist_index, location_index = location_index, object_index = object_index}
				end
            end
        end

        if object_data.type == "vehicle" then
			table.insert(addon_components.vehicles, object_data)
        elseif object_data.type == "character" then
			table.insert(addon_components.survivors, object_data)
		elseif object_data.type == "fire" then
			table.insert(addon_components.fires, object_data)
        elseif object_data.type == "object" then
            table.insert(addon_components.objects, object_data)
		elseif object_data.type == "zone" then
			table.insert(addon_components.zones, object_data)
        end
    end

    if is_valid_location then
    	table.insert(built_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = addon_components} )
    end
end

function spawnObjects(spawn_transform, playlist_index, location_index, object_descriptors, out_spawned_objects)
	local spawned_objects = {}

	for _, object in pairs(object_descriptors) do
		-- find parent vehicle id if set

		local parent_vehicle_id = 0
		if object.vehicle_parent_component_id > 0 then
			for spawned_object_id, spawned_object in pairs(out_spawned_objects) do
				if spawned_object.type == "vehicle" and spawned_object.component_id == object.vehicle_parent_component_id then
					parent_vehicle_id = spawned_object.id
				end
			end
		end

		spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
	end

	return spawned_objects
end

function spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
	-- spawn object

	local spawned_object_id = spawnObjectType(m.multiply(spawn_transform, object.transform), playlist_index, location_index, object, parent_vehicle_id)

	-- add object to spawned object tables

	if spawned_object_id ~= nil and spawned_object_id ~= 0 then

		local l_ai_type = AI_TYPE_HELI
		if hasTag(object.tags, "type=wep_plane") then
			l_ai_type = AI_TYPE_PLANE
		end
		if hasTag(object.tags, "type=wep_boat") then
			l_ai_type = AI_TYPE_BOAT
		end
		if hasTag(object.tags, "type=wep_land") then
			l_ai_type = AI_TYPE_LAND
		end
		if hasTag(object.tags, "type=wep_turret") then
			l_ai_type = AI_TYPE_TURRET
		end
		if hasTag(object.tags, "from=dlc_weapons_flag") then
			l_ai_type = "flag"
		end
		if hasTag(object.tags, "from=dlc_weapons_terrain_scanner") then
			wpDLCDebug("terrain scanner!", true, false)
			l_ai_type = "terrain_scanner"
		end

		local l_size = "small"
		for tag_index, tag_object in pairs(object.tags) do
			if string.find(tag_object, "size=") ~= nil then
				l_size = string.sub(tag_object, 6)
			end
		end

		local object_data = { name = object.display_name, type = object.type, id = spawned_object_id, component_id = object.id, ai_type = l_ai_type, size = l_size }

		if spawned_objects ~= nil then
			table.insert(spawned_objects, object_data)
		end

		if out_spawned_objects ~= nil then
			table.insert(out_spawned_objects, object_data)
		end

		return object_data
	end

	return nil
end

-- spawn an individual object descriptor from a playlist location
function spawnObjectType(spawn_transform, playlist_index, location_index, object_descriptor, parent_vehicle_id)
	local component = s.spawnAddonComponent(spawn_transform, playlist_index, location_index, object_descriptor.index, parent_vehicle_id)
	return component.id
end

--------------------------------------------------------------------------------
--
-- VEHICLE HELPERS
--
--------------------------------------------------------------------------------

function isVehicleNeedsResupply(vehicle_id)
	local button_data, success = s.getVehicleButton(vehicle_id, "Resupply")
	return success and button_data.on
end

function isVehicleNeedsReloadMG(vehicle_id)
	local needing_reload = false
	local mg_id = 0
	for i=1,6 do
		local needs_reload, is_success_button = s.getVehicleButton(vehicle_id, "RELOAD_MG"..i)
		if needs_reload ~= nil then
			if needs_reload.on and is_success_button then
				needing_reload = true
				mg_id = i
			end
		end
	end
	local returnings = {}
	returnings[1] = needing_reload
	returnings[2] = mg_id
	return returnings
end



--------------------------------------------------------------------------------
--
-- SQUAD HELPERS
--
--------------------------------------------------------------------------------

function resetSquadTarget(squad)
	squad.target_island = nil
end

function setSquadCommandPatrol(squad, target_island)
	squad.target_island = target_island
	setSquadCommand(squad, COMMAND_PATROL)
end

function setSquadCommandStage(squad, target_island)
	squad.target_island = target_island
	setSquadCommand(squad, COMMAND_STAGE)
end

function setSquadCommandAttack(squad, target_island)
	squad.target_island = target_island
	setSquadCommand(squad, COMMAND_ATTACK)
end

function setSquadCommandDefend(squad, target_island)
	squad.target_island = target_island
	setSquadCommand(squad, COMMAND_DEFEND)
end

function setSquadCommandEngage(squad)
	setSquadCommand(squad, COMMAND_ENGAGE)
end

function setSquadCommandInvestigate(squad, investigate_transform)
	squad.investigate_transform = investigate_transform
	setSquadCommand(squad, COMMAND_INVESTIGATE)
end

function setSquadCommandScout(squad)
	setSquadCommand(squad, COMMAND_SCOUT)
end

function setSquadCommand(squad, command)
	if squad.command ~= command and squad.command ~= COMMAND_SCOUT then
		squad.command = command
	
		for vehicle_id, vehicle_object in pairs(squad.vehicles) do
			squadInitVehicleCommand(squad, vehicle_object)
		end

		if squad.command == COMMAND_NONE then
			resetSquadTarget(squad)
		elseif squad.command == COMMAND_INVESTIGATE then
			squad.target_players = {}
			squad.target_vehicles = {}
		end

		return true
	end

	return false
end

function squadInitVehicleCommand(squad, vehicle_object)
	vehicle_object.target_vehicle_id = -1
	vehicle_object.target_player_id = -1

	wpDLCDebugVehicle(vehicle_object.id, "(squadInitVehicleCommand) Vehicle "..vehicle_object.id.." command: "..squad.command, true, false)

	if squad.command == COMMAND_PATROL then
		resetPath(vehicle_object)

		local patrol_route = g_patrol_route
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(patrol_route[1].x, CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), patrol_route[1].z)))
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(patrol_route[2].x, CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), patrol_route[2].z)))
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(patrol_route[3].x, CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), patrol_route[3].z)))
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(patrol_route[4].x, CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), patrol_route[4].z)))
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(patrol_route[5].x, CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), patrol_route[5].z)))
	elseif squad.command == COMMAND_ATTACK then
		-- go to island, once island is captured the command will be cleared
		resetPath(vehicle_object)
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(math.random(-500, 500), CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), math.random(-500, 500))))
	elseif squad.command == COMMAND_STAGE then
		resetPath(vehicle_object)
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(math.random(-500, 500), CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), math.random(-500, 500))))
	elseif squad.command == COMMAND_DEFEND then
		-- go to island, remain there indefinitely
		resetPath(vehicle_object)
		addPath(vehicle_object, m.multiply(squad.target_island.transform, m.translation(math.random(-500, 500), CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), math.random(-500, 500))))
	elseif squad.command == COMMAND_INVESTIGATE then
		-- go to investigate location
		resetPath(vehicle_object)
		addPath(vehicle_object, m.multiply(squad.investigate_transform, m.translation(math.random(-500, 500), CRUISE_HEIGHT + (vehicle_object.id % 10 * 20), math.random(-500, 500))))
	elseif squad.command == COMMAND_ENGAGE then
		resetPath(vehicle_object)
	elseif squad.command == COMMAND_SCOUT then
		resetPath(vehicle_object)
		target_island, origin_island = getObjectiveIsland()
		if target_island then
			wpDLCDebug("Scout found a target island!", true, false)
			local holding_route = g_holding_pattern
			addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[1].x, CRUISE_HEIGHT * 2, holding_route[1].z)))
			addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[2].x, CRUISE_HEIGHT * 2, holding_route[2].z)))
			addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[3].x, CRUISE_HEIGHT * 2, holding_route[3].z)))
			addPath(vehicle_object, m.multiply(target_island.transform, m.translation(holding_route[4].x, CRUISE_HEIGHT * 2, holding_route[4].z)))
		else
			wpDLCDebug("Scout was unable to find a island to target!", true, true)
		end
	elseif squad.command == COMMAND_RETREAT then
	elseif squad.command == COMMAND_NONE then
	elseif squad.command == COMMAND_TURRET then
		resetPath(vehicle_object)
	elseif squad.command == COMMAND_RESUPPLY then
		resetPath(vehicle_object)
	end
end

function squadGetVisionData(squad)
	local vision_data = {
		visible_players_map = {},
		visible_players = {},
		visible_vehicles_map = {},
		visible_vehicles = {},
		investigate_players = {},
		investigate_vehicles = {},

		isPlayerVisible = function(self, id)
			return self.visible_players_map[id] ~= nil
		end,

		isVehicleVisible = function(self, id)
			return self.visible_vehicles_map[id] ~= nil
		end,

		getBestTargetPlayerID = function(self)
			return self.visible_players[math.random(1, #self.visible_players)].id
		end,

		getBestTargetVehicleID = function(self)
			return self.visible_vehicles[math.random(1, #self.visible_vehicles)].id
		end,

		getBestInvestigatePlayer = function(self)
			return self.investigate_players[math.random(1, #self.investigate_players)]
		end,

		getBestInvestigateVehicle = function(self)
			return self.investigate_vehicles[math.random(1, #self.investigate_vehicles)]
		end,

		is_engage = function(self)
			return #self.visible_players > 0 or #self.visible_vehicles > 0
		end,

		is_investigate = function(self)
			return #self.investigate_players > 0 or #self.investigate_vehicles > 0
		end,
	}

	for object_id, player_object in pairs(squad.target_players) do
		local player_data = { id = object_id, obj = player_object }

		if player_object.state == TARGET_VISIBILITY_VISIBLE then
			vision_data.visible_players_map[object_id] = player_data
			table.insert(vision_data.visible_players, player_data)
		elseif player_object.state == TARGET_VISIBILITY_INVESTIGATE then
			table.insert(vision_data.investigate_players, player_data)
		end
	end

	for vehicle_id, vehicle_object in pairs(squad.target_vehicles) do
		local vehicle_data = { id = vehicle_id, obj = vehicle_object }

		if vehicle_object.state == TARGET_VISIBILITY_VISIBLE then
			vision_data.visible_vehicles_map[vehicle_id] = vehicle_data
			table.insert(vision_data.visible_vehicles, vehicle_data)
		elseif vehicle_object.state == TARGET_VISIBILITY_INVESTIGATE then
			table.insert(vision_data.investigate_vehicles, vehicle_data)
		end
	end

	return vision_data
end


--------------------------------------------------------------------------------
--
-- UTILITIES
--
--------------------------------------------------------------------------------

---@param id integer the tick you want to check that it is
---@param rate integer the total amount of ticks, for example, a rate of 60 means it returns true once every second* (if the tps is not low)
---@return boolean isTick if its the current tick that you requested
function isTickID(id, rate)
	return (g_tick_counter + id) % rate == 0
end

-- iterator function for iterating over all playlists, skipping any that return nil data
function iterPlaylists()
	local playlist_count = s.getAddonCount()
	local playlist_index = 0

	return function()
		local playlist_data = nil
		local index = playlist_count

		while playlist_data == nil and playlist_index < playlist_count do
			playlist_data = s.getAddonData(playlist_index)
			index = playlist_index
			playlist_index = playlist_index + 1
		end

		if playlist_data ~= nil then
			return index, playlist_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all locations in a playlist, skipping any that return nil data
function iterLocations(playlist_index)
	local playlist_data = s.getAddonData(playlist_index)
	local location_count = 0
	if playlist_data ~= nil then location_count = playlist_data.location_count end
	local location_index = 0

	return function()
		local location_data = nil
		local index = location_count

		while not location_data and location_index < location_count do
			location_data = s.getLocationData(playlist_index, location_index)
			index = location_index
			location_index = location_index + 1
		end

		if location_data ~= nil then
			return index, location_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all objects in a location, skipping any that return nil data
function iterObjects(playlist_index, location_index)
	local location_data = s.getLocationData(playlist_index, location_index)
	local object_count = 0
	if location_data ~= nil then object_count = location_data.component_count end
	local object_index = 0

	return function()
		local object_data = nil
		local index = object_count

		while not object_data and object_index < object_count do
			object_data = s.getLocationComponentData(playlist_index, location_index, object_index)
			object_data.index = object_index
			index = object_index
			object_index = object_index + 1
		end

		if object_data ~= nil then
			return index, object_data
		else
			return nil
		end
	end
end

function hasTag(tags, tag)
	if type(tags) == "table" then
		for k, v in pairs(tags) do
			if v == tag then
				return true
			end
		end
	else
		wpDLCDebug("hasTag() was expecting a table, but got a "..type(tags).." instead!", true, true)
	end
	return false
end

-- gets the value of the specifed tag, returns nil if tag not found
function getTagValue(tags, tag, as_string)
	if type(tags) == "table" then
		for k, v in pairs(tags) do
			if string.match(v, tag.."=") then
				if not as_string then
					return tonumber(tostring(string.gsub(v, tag.."=", "")))
				else
					return tostring(string.gsub(v, tag.."=", ""))
				end
			end
		end
	else
		wpDLCDebug("getTagValue() was expecting a table, but got a "..type(tags).." instead!", true, true)
	end
	return nil
end

-- prints all in a table
function printTable(T, requiresDebugging, isError, toPlayer)
	for k, v in pairs(T) do
		if type(v) == "table" then
			wpDLCDebug("Table: "..tostring(k), requiresDebugging, isError, toPlayer)
			printTable(v, requiresDebugging, isError, toPlayer)
		else
			wpDLCDebug("k: "..tostring(k).." v: "..tostring(v), requiresDebugging, isError, toPlayer)
		end
	end
end

function tabulate(t,...) -- credit: woe | for this function
	local _ = table.pack(...)
	t[_[1]] = t[_[1]] or {}
	if _.n>1 then
		tabulate(t[_[1]], table.unpack(_, 2))
	end
end

function rand(x, y)
	return math.random()*(y-x)+x
end

function randChance(t)
	local total_mod = 0
	for k, v in pairs(t) do
		total_mod = total_mod + v
	end
	local win_name = ""
	local win_val = 0
	for k, v in pairs(t) do
		local chance = rand(0, v / total_mod)
		wpDLCDebug("chance: "..chance.." chance to beat: "..win_val.." k: "..k, true, false)
		if chance > win_val then
			win_val = chance
			win_name = k
		end
	end
	return win_name
end

function spawnModifiers.create() -- populates the constructable vehicles with their spawning modifiers
	for role, role_data in pairs(g_savedata.constructable_vehicles) do
		if type(role_data) == "table" then
			if role == "attack" or role == "general" or role == "defend" or role == "roaming" or role == "stealth" or role == "scout" then
				for veh_type, veh_data in pairs(g_savedata.constructable_vehicles[role]) do
					if veh_type ~= "mod" and type(veh_data) == "table"then
						for strat, strat_data in pairs(veh_data) do
							if type(strat_data) == "table" and strat ~= "mod" then
								g_savedata.constructable_vehicles[role][veh_type][strat].mod = 1
								for vehicle_id, v in pairs(strat_data) do
									if type(v) == "table" and vehicle_id ~= "mod" then
										g_savedata.constructable_vehicles[role][veh_type][strat][vehicle_id].mod = 1
									end
								end
							end
						end
						g_savedata.constructable_vehicles[role][veh_type].mod = 1
					end
				end
				g_savedata.constructable_vehicles[role].mod = default_mods[role]
			end
		end
	end
end

---@param is_specified boolean true to specify what vehicle to spawn, false for random
---@param vehicle_list_id any vehicle to spawn if is_specified is true, integer to specify exact vehicle, string to specify the role of the vehicle you want
---@return prefab_data[] prefab_data the vehicle's prefab data
function spawnModifiers.spawn(is_specified, vehicle_list_id)
	local sel_role = nil
	local sel_veh_type = nil
	local sel_strat = nil
	local sel_vehicle = nil
	if is_specified == true and type(vehicle_list_id) == "number" then
		sel_role = g_savedata.vehicle_list[vehicle_list_id].role
		sel_veh_type = g_savedata.vehicle_list[vehicle_list_id].vehicle_type
		sel_strat = g_savedata.vehicle_list[vehicle_list_id].strategy
		for vehicle_id, vehicle_object in pairs(g_savedata.constructable_vehicles[sel_role][sel_veh_type][sel_strat]) do
			if not sel_vehicle and vehicle_list_id == g_savedata.constructable_vehicles[sel_role][sel_veh_type][sel_strat][vehicle_id].id then
				sel_vehicle = vehicle_id
			end
		end
		if not sel_vehicle then
			return false
		end
	elseif is_specified == false or type(vehicle_list_id) == "string" then
		local role_chances = {}
		local veh_type_chances = {}
		local strat_chances = {}
		local vehicle_chances = {}
		if not vehicle_list_id then
			for role, v in pairs(g_savedata.constructable_vehicles) do
				if type(v) == "table" then
					if role == "attack" or role == "general" or role == "defend" or role == "roaming" then
						role_chances[role] = g_savedata.constructable_vehicles[role].mod
					end
				end
			end
			sel_role = randChance(role_chances)
		else
			sel_role = vehicle_list_id
		end
		for veh_type, v in pairs(g_savedata.constructable_vehicles[sel_role]) do
			if type(v) == "table" then
				veh_type_chances[veh_type] = g_savedata.constructable_vehicles[sel_role][veh_type].mod
			end
		end
		sel_veh_type = randChance(veh_type_chances)
		for strat, v in pairs(g_savedata.constructable_vehicles[sel_role][sel_veh_type]) do
			if type(v) == "table" then
				strat_chances[strat] = g_savedata.constructable_vehicles[sel_role][sel_veh_type][strat].mod
			end
		end
		sel_strat = randChance(strat_chances)
		for vehicle, v in pairs(g_savedata.constructable_vehicles[sel_role][sel_veh_type][sel_strat]) do
			if type(v) == "table" then
				vehicle_chances[vehicle] = g_savedata.constructable_vehicles[sel_role][sel_veh_type][sel_strat][vehicle].mod
			end
		end
		sel_vehicle = randChance(vehicle_chances)
	else
		wpDLCDebug("unknown arguments for choosing which ai vehicle to spawn!", true, true)
		return false
	end
	return g_savedata.constructable_vehicles[sel_role][sel_veh_type][sel_strat][sel_vehicle]
end

---@param role string the role of the vehicle, such as attack, general or defend
---@param type string the vehicle type, such as boat, plane, heli, land or turret
---@param strategy string the strategy of the vehicle, such as strafe, bombing or general
---@param vehicle_list_id integer the index of the vehicle in the vehicle list
---@return integer constructable_vehicle_id the index of the vehicle in the constructable vehicle list, returns nil if not found
function spawnModifiers.getConstructableVehicleID(role, type, strategy, vehicle_list_id)
	local constructable_vehicle_id = nil
	if g_savedata.constructable_vehicles[role][type][strategy] then
		for vehicle_id, vehicle_object in pairs(g_savedata.constructable_vehicles[role][type][strategy]) do
			if not constructable_vehicle_id and vehicle_list_id == g_savedata.constructable_vehicles[role][type][strategy][vehicle_id].id then
				constructable_vehicle_id = vehicle_id
			end
		end
	end
	return constructable_vehicle_id -- returns the constructable_vehicle_id, if not found then it returns nil
end

---@param vehicle_name string the name of the vehicle
---@return integer vehicle_list_id the vehicle list id from the vehicle's name, returns nil if not found
function spawnModifiers.getVehicleListID(vehicle_name)
	local found_vehicle = nil
	for vehicle_id, vehicle_object in pairs(g_savedata.vehicle_list) do
		wpDLCDebug(vehicle_object.location.data.name)
		if vehicle_object.location.data.name == vehicle_name and not found_vehicle then
			found_vehicle = vehicle_id
		end
	end
	return found_vehicle
end

---@param reinforcement_type string \"punish\" to make it less likely to spawn, \"reward\" to make it more likely to spawn
---@param role string the role of the vehicle, such as attack, general or defend
---@param role_reinforcement integer how much to reinforce the role of the vehicle, 1-5
---@param type string the vehicle type, such as boat, plane, heli, land or turret
---@param type_reinforcement integer how much to reinforce the type of the vehicle, 1-5
---@param strategy string strategy of the vehicle, such as strafe, bombing or general
---@param strategy_reinforcement integer how much to reinforce the strategy of the vehicle, 1-5
---@param constructable_vehicle_id integer the index of the vehicle in the constructable vehicle list
---@param vehicle_reinforcement integer how much to reinforce the vehicle, 1-5
function spawnModifiers.train(reinforcement_type, role, role_reinforcement, type, type_reinforcement, strategy, strategy_reinforcement, constructable_vehicle_id, vehicle_reinforcement)
	if reinforcement_type == PUNISH then
		if role and role_reinforcement then
			wpDLCDebug("punished role:"..role.." | amount punished: "..ai_training.punishments[role_reinforcement], true, false)
			g_savedata.constructable_vehicles[role].mod = math.max(g_savedata.constructable_vehicles[role].mod + ai_training.punishments[role_reinforcement], 0)
			if type and type_reinforcement then 
				wpDLCDebug("punished type:"..type.." | amount punished: "..ai_training.punishments[type_reinforcement], true, false)
				g_savedata.constructable_vehicles[role][type].mod = math.max(g_savedata.constructable_vehicles[role][type].mod + ai_training.punishments[type_reinforcement], 0.05)
				if strategy and strategy_reinforcement then 
					wpDLCDebug("punished strategy:"..strategy.." | amount punished: "..ai_training.punishments[strategy_reinforcement], true, false)
					g_savedata.constructable_vehicles[role][type][strategy].mod = math.max(g_savedata.constructable_vehicles[role][type][strategy].mod + ai_training.punishments[strategy_reinforcement], 0.05)
					if constructable_vehicle_id and vehicle_reinforcement then 
						wpDLCDebug("punished vehicle:"..constructable_vehicle_id.." | amount punished: "..ai_training.punishments[vehicle_reinforcement], true, false)
						g_savedata.constructable_vehicles[role][type][strategy][constructable_vehicle_id].mod = math.max(g_savedata.constructable_vehicles[role][type][strategy][constructable_vehicle_id].mod + ai_training.punishments[vehicle_reinforcement], 0.05)
					end
				end
			end
		end
	elseif reinforcement_type == REWARD then
		if role and role_reinforcement then
			wpDLCDebug("rewarded role:"..role.." | amount rewarded: "..ai_training.rewards[role_reinforcement], true, false)
			g_savedata.constructable_vehicles[role].mod = math.min(g_savedata.constructable_vehicles[role].mod + ai_training.rewards[role_reinforcement], 1.5)
			if type and type_reinforcement then 
				wpDLCDebug("rewarded type:"..type.." | amount rewarded: "..ai_training.rewards[type_reinforcement], true, false)
				g_savedata.constructable_vehicles[role][type].mod = math.min(g_savedata.constructable_vehicles[role][type].mod + ai_training.rewards[type_reinforcement], 1.5)
				if strategy and strategy_reinforcement then 
					wpDLCDebug("rewarded strategy:"..strategy.." | amount rewarded: "..ai_training.rewards[strategy_reinforcement], true, false)
					g_savedata.constructable_vehicles[role][type][strategy].mod = math.min(g_savedata.constructable_vehicles[role][type][strategy].mod + ai_training.rewards[strategy_reinforcement], 1.5)
					if constructable_vehicle_id and vehicle_reinforcement then 
						wpDLCDebug("rewarded vehicle:"..constructable_vehicle_id.." | amount rewarded: "..ai_training.rewards[vehicle_reinforcement], true, false)
						g_savedata.constructable_vehicles[role][type][strategy][constructable_vehicle_id].mod = math.min(g_savedata.constructable_vehicles[role][type][strategy][constructable_vehicle_id].mod + ai_training.rewards[vehicle_reinforcement], 1.5)
					end
				end
			end
		end
	end
end

---@param user_peer_id integer the peer_id of the player who executed the command
---@param role string the role of the vehicle, such as attack, general or defend
---@param type string the vehicle type, such as boat, plane, heli, land or turret
---@param strategy string strategy of the vehicle, such as strafe, bombing or general
---@param constructable_vehicle_id integer the index of the vehicle in the constructable vehicle list
function spawnModifiers.debug(user_peer_id, role, type, strategy, constructable_vehicle_id)
	if not constructable_vehicle_id then
		if not strategy then
			if not type then
				wpDLCDebug("modifier of vehicles with role "..role..": "..g_savedata.constructable_vehicles[role].mod, false, false, user_peer_id)
			else
				wpDLCDebug("modifier of vehicles with role "..role..", with type "..type..": "..g_savedata.constructable_vehicles[role][type].mod, false, false, user_peer_id)
			end
		else
			wpDLCDebug("modifier of vehicles with role "..role..", with type "..type..", with strategy "..strategy..": "..g_savedata.constructable_vehicles[role][type][strategy].mod, false, false, user_peer_id)
		end
	else
		wpDLCDebug("modifier of role "..role..", type "..type..", strategy "..strategy..", with the id of "..constructable_vehicle_id..": "..g_savedata.constructable_vehicles[role][type][strategy][constructable_vehicle_id].mod, false, false, user_peer_id)
	end
end

---@param matrix1 Matrix the first matrix
---@param matrix2 Matrix the second matrix
function xzDistance(matrix1, matrix2) -- returns the distance between two matrixes, ignoring the y axis
	ox, oy, oz = m.position(matrix1)
	tx, ty, tz = m.position(matrix2)
	return m.distance(m.translation(ox, 0, oz), m.translation(tx, 0, tz))
end

---@param player_list Players[] the list of players to check
---@param target_pos Matrix the position that you want to check
---@param min_dist number the minimum distance between the player and the target position
---@param ignore_y boolean if you want to ignore the y level between the two or not
---@return boolean no_players_nearby returns true if theres no players which distance from the target_pos was less than the min_dist
function playersNotNearby(player_list, target_pos, min_dist, ignore_y)
	local players_clear = true
	for player_index, player in pairs(player_list) do
		if ignore_y and xzDistance(s.getPlayerPos(player_index), target_pos) < min_dist then
			players_clear = false
		elseif not ignore_y and m.distance(s.getPlayerPos(player_index), target_pos) < min_dist then
			players_clear = false
		end
	end
	return players_clear
end

---@param T table table to get the size of
---@return number count the size of the table
function tableLength(T)
	if T ~= nil then
		local count = 0
		for _ in pairs(T) do count = count + 1 end
		return count
	else return 0 end
end

---@param x number the number to clamp
---@param min number the minimum value
---@param max number the maximum value
---@return number clamped_x the number clamped between the min and max
function math.clamp(x, min, max)
    return max<x and max or min>x and min or x
end