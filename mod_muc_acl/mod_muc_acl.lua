local st = require "util.stanza";
local jid = require "util.jid";
local nodeprep = require "util.encodings".stringprep.nodeprep;

local unprepped_access_lists = module:get_option("muc_acls", {});
local unprepped_public_rooms = module:get_option("muc_acl_public_rooms", {});
local unprepped_default_acl = module:get_option("muc_acl_default", {});
local restriced_by_default = module:get_option_boolean("muc_acl_restricted_by_default", false);
local debug = module:get_option_boolean("muc_acl_debug", false);

local public_rooms = {};

local room_acls = {};
local default_acl = {};

module:log("error", "Loading MUC ACLs...");

function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

local function prepare_jid_list(jid_list)
	local prepared_jid_list = {}

	for _, unprepped_jid in ipairs(jid_list) do
		local prepped_jid = jid.prep(unprepped_jid);

		if not prepped_jid then
			module:log("error", "Invalid JID: %s", unprepped_jid);
		else
			table.insert(prepared_jid_list, prepped_jid);
		end
	end

	return prepared_jid_list
end

-- Make sure all input is prepped
if not type(unprepped_access_lists) == 'table' then
	module:log("error", "muc_default_acl must be a table.")
else
	for unprepped_room_name, unprepped_list in pairs(unprepped_access_lists) do
		module:log("error", "unprepped_room_name: %s", unprepped_room_name);
		local prepped_room_name = nodeprep(unprepped_room_name);
		if not prepped_room_name then
			module:log("error", "Invalid room name: %s", unprepped_room_name);
		else
			room_acls[prepped_room_name] = Set(prepare_jid_list(unprepped_list));
		end
	end
end

if not type(unprepped_public_rooms) == 'table' then
	module:log("error", "muc_access_public must be a table.")
else
	if #unprepped_public_rooms > 0 and not restriced_by_default then
		module:log("warn", "A list of public rooms does not make sense, "
			.. "if room access is not restricted by default. "
			.. "The list will be ignored.");
	elseif #unprepped_public_rooms > 0 and restriced_by_default then
		local public_rooms_list = {}
		for _, unprepped_room_name in pairs(unprepped_public_rooms) do
			local prepped_room_name = nodeprep(unprepped_room_name);
			if not prepped_room_name then
				module:log("error", "Invalid room name (in public_rooms): %s", unprepped_room_name);
			else
				table.insert(public_rooms_list, unprepped_room_name);
			end
		end
		public_rooms = Set(public_rooms_list);
	end
end


if not type(unprepped_default_acl) == 'table' then
	module:log("error", "muc_default_acl must be a table.")
else
	if #unprepped_default_acl > 0 and not restriced_by_default then
		module:log("warn", "default_acl will be ignored because "
			.. "muc_acl_restricted_by_default is not set.");
	elseif #unprepped_default_acl > 0 and restriced_by_default then
		default_acl = Set(prepare_jid_list(unprepped_default_acl));
	end
end

if debug then
	local list = "";
	for room_name, room_acl in pairs(room_acls) do
		list = "";
		for acl_name, _ in pairs(room_acl) do
			list = list .. tostring(acl_name) .. ", ";
		end
		module:log("debug", "ACL for room %s: %s", room_name, list);
	end

	module:log("debug", "Rooms are " .. (restriced_by_default and '' or 'not') .. " restricted by default");
	list = "";
	for _, room_name in pairs(public_rooms) do
		list = list .. tostring(room_name) .. ", ";
	end
	module:log("debug", "Public rooms: %s", list);

	list = "";
	for _, acl_name in pairs(default_acl) do
		list = list .. tostring(acl_name) .. ", ";
	end
	module:log("debug", "Default ACL: %s", list);
end


local function is_restricted(room, who)
	local allowed = room_acls[room];

	-- A client is allowed to join, if ...
	-- ... the room is marked public (only applies when restriced_by_default is set)
	-- ... the room is public, since restriced_by_default is false and it has not been
	-- 		restricted otherwise.
	-- ... the room is private and has an ACL, which contains the user's jid or domain
	-- ... the room is private, since restriced_by_default is true and the user's jid/domain is in
	-- 		the default_acl list

	if allowed == nil or allowed[who] or allowed[select(2, jid.split(who))] then
		return nil;
	end

	return "forbidden";
end

module:hook("presence/full", function(event)
        local stanza = event.stanza;

        if stanza.name == "presence" and stanza.attr.type == "unavailable" then   -- Leaving events get discarded
                return;
        end

	-- Get the room
	local room = jid.split(stanza.attr.to);
        if not room then return; end

	-- Get who has tried to join it
	local who = jid.bare(stanza.attr.from)

	-- Checking whether room is restricted
	local check_restricted = is_restricted(room, who)
        if check_restricted ~= nil then
                event.allowed = false;
                event.stanza.attr.type = 'error';
	        return event.origin.send(st.error_reply(event.stanza, "cancel", "forbidden", "You're not allowed to enter this room: " .. check_restricted));
        end
end, 10);
