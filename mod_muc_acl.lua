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

module:log("info", "Loading MUC ACLs...");

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
if type(unprepped_access_lists) ~= 'table' then
	module:log("error", "muc_acls must be a table (is %s).", type(unprepped_access_lists));
else
	for unprepped_room_name, unprepped_list in pairs(unprepped_access_lists) do
		local prepped_room_name = nodeprep(unprepped_room_name);
		if not prepped_room_name then
			module:log("error", "Invalid room name: %s", unprepped_room_name);
		else
			room_acls[prepped_room_name] = Set(prepare_jid_list(unprepped_list));
		end
	end
end

if type(unprepped_public_rooms) ~= 'table' then
	module:log("error", "muc_access_public must be a table (is %s).", type(unprepped_public_rooms))
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


if type(unprepped_default_acl) ~= 'table' then
	module:log("error", "muc_acl_default must be a table.")
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
		module:log("debug", "ACL for room %s: { %s }", room_name, list);
	end

	module:log("debug", "Rooms are " .. (restriced_by_default and "" or "not ") .. "restricted by default");
	list = "";
	for room_name, _ in pairs(public_rooms) do
		list = list .. tostring(room_name) .. ", ";
	end
	module:log("debug", "Public rooms: { %s }", list);

	list = "";
	for acl_name, _ in pairs(default_acl) do
		list = list .. tostring(acl_name) .. ", ";
	end
	module:log("debug", "Default ACL: { %s }", list);
end


local function check_acl_for_jid(acl, who)
	return acl ~= nil and (acl[who] or acl[select(2, jid.split(who))]);
end

local function is_restricted(room, who)
	-- A client is allowed to join, if ...
	-- ... the room is marked public (only applies when restriced_by_default is set)
	-- ... the room is public, since restriced_by_default is false and it has not been
	-- 		restricted otherwise.
	-- ... the room is private and has an ACL, which contains the user's jid or domain
	-- ... the room is private, since restriced_by_default is true and the user's jid/domain is in
	-- 		the default_acl list
	local rv = true;

	if restriced_by_default and ( public_rooms[room] ~= nil or check_acl_for_jid(default_acl, who)) then
		rv = false;
	elseif (not restriced_by_default) and room_acls[room] == nil then
		rv = false;
	end

	if rv and room_acls[room] ~= nil and check_acl_for_jid(room_acls[room], who) then
		rv = false;
	end

	module:log("info", "%s tried to join %s: Access %s.", who, room,
		(rv and "denied" or "granted")
	);
	return rv;
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
    if is_restricted(room, who) then
            event.allowed = false;
            event.stanza.attr.type = 'error';
	    return event.origin.send(st.error_reply(event.stanza, "cancel", "forbidden",
			"You're not allowed to enter this room: forbidden."));
    end
end, 10);
