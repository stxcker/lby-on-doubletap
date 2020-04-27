-- [x]==============================[ UI References ]==============================[x]
local doubletap, doubletap_state = ui.reference( "Rage", "Other", "Double tap" )
local lby_target = ui.reference( "AA", "Anti-aimbot angles", "Lower body yaw target" )
local limit = ui.reference( "AA", "Fake lag", "Limit" )
local pitch = ui.reference( "AA", "Anti-aimbot angles", "Pitch" )

-- [x]==[ Requires ]==[x]
local ffi = require "ffi"

-- [x]=====================[ C Defenitions ]=====================[x]
ffi.cdef[[	
    typedef void*( __thiscall* get_client_entity_fn )( void*, int );

	struct c_animstate {
		void *this_ptr;
		char pad[ 0xE7 ];
		float speed2d;
	};
]]

-- [x]=====================================================[ Interfaces ]=====================================================[x]
local entity_list = ffi.cast( ffi.typeof( "void***" ), client.create_interface( "client_panorama.dll", "VClientEntityList003" ) )

-- [x]==========================[ Interface Functions ]==========================[x]
local get_client_entity = ffi.cast( "get_client_entity_fn", entity_list[ 0 ][ 3 ] )

-- [x]============[ Data Structures ]============[x]
local function vec_3( _x, _y, _z ) 
	return { x = _x or 0, y = _y or 0, z = _z or 0 } 
end

-- [x]========================================[ Math Functions ]========================================[x]
function round( x ) -- https://stackoverflow.com/questions/18313171/lua-rounding-numbers-and-then-truncate
    return x >= 0 and math.floor( x+0.5 ) or math.ceil( x-0.5 )
end

local function normalize_as_yaw( yaw )
	if yaw > 180 or yaw < -180 then
		local revolutions = round( math.abs( yaw / 360 ) )

		if yaw < 0 then
			yaw = yaw + 360 * revolutions
		else
			yaw = yaw - 360 * revolutions
		end
	end

	return yaw
end

local function ticks_to_time( ticks )
	return globals.tickinterval( ) * ticks
end 

local function time_to_ticks( input )
	return ( ( 0.5 + ( input ) / globals.tickinterval( ) ) )
end

-- [x]======================================[ Local Functions ]======================================[x]
local function on_ground( ply ) -- Credits to somebody lol
    local flags = entity.get_prop( ply, "m_fFlags" )
    return bit.band( flags, bit.lshift( 1, 0 ) ) == 1 -- Cast to bool
end

local next_lby_update_time = 0
local time_to_send = false
local function next_lby_update( cmd )
	local curtime = globals.curtime( )
	
    local user_ptr = ffi.cast( "void***", get_client_entity( entity_list, entity.get_local_player( ) ) )
	local animstate_ptr = ffi.cast( "char*" , user_ptr ) + 0x3900
	local user_animstate = ffi.cast( "struct c_animstate**", animstate_ptr )[ 0 ]
	
	if not on_ground( entity.get_local_player( ) ) then
		return false
	end

	if user_animstate.speed2d > 0.1 then
		next_lby_update_time = curtime + 0.22;
	end
	
	if time_to_ticks( next_lby_update_time ) - 4 < time_to_ticks( curtime ) and time_to_send then
		cmd.allow_send_packet = true
		time_to_send = false
	end
	
	if next_lby_update_time < curtime then
		next_lby_update_time = curtime + 1.1;
		time_to_send = true
		return true
	end

	return false
end

-- [x]============================================[ Callbacks ]============================================[x]
local stored = 0
local once = false
local force_update = false
local set_limit = false
client.set_event_callback( "setup_command", function( cmd )
	-- Setup angles
	local eye_angles = vec_3( entity.get_prop( entity.get_local_player( ), "m_angEyeAngles" ) )
	local real_angles = vec_3( entity.get_prop( entity.get_local_player( ), "m_angAbsRotation" ) )
	local fake_side = ( normalize_as_yaw( real_angles.y - eye_angles.y ) > 0 ) and -1 or 1
	
	-- Get velocity
	local velocity_prop = vec_3( entity.get_prop( entity.get_local_player( ), "m_vecVelocity" ) )
	local velocity = math.sqrt( velocity_prop.x * velocity_prop.x + velocity_prop.y * velocity_prop.y )

	-- Prevent velocity from fucking shit up
	if ui.get( doubletap ) and ui.get( doubletap_state ) then
		if ui.get( lby_target ) == "Opposite" and not once then
			ui.set( lby_target, "Off" )
			force_update = true
			stored = globals.tickcount( ) + 11 + ui.get( limit ) + 1
			once = true
		end
		
		-- Sorryyy...
		local scoped = entity.get_prop( entity.get_local_player( ), "m_bIsScoped" )
		if scoped then
			if ( globals.tickcount( ) >= stored + 1 ) and force_update then
				cmd.forwardmove = 450
				if stored + 1 == globals.tickcount( ) then
					force_update = false
				end
			end
		else
			if stored == globals.tickcount( ) and force_update then
				cmd.forwardmove = 450
				force_update = false
			end
		end

	else
		if once then
			ui.set( lby_target, "Opposite" )
			once = false
		end
	end
	
	if next_lby_update( cmd ) and ui.get( lby_target ) == "Off" then
		if ui.get( pitch ) ~= "Off" then
			if ui.get( pitch ) == "Up" then
				cmd.pitch = -90
			elseif ui.get( pitch ) == "Down" then
				cmd.pitch = 90
			else
				cmd.pitch = 89
			end
		end
		cmd.yaw = normalize_as_yaw( eye_angles.y + ( 60 * fake_side ) )
	end
end )