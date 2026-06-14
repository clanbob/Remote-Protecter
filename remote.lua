local module = {}

local network = require(script.Parent.Remotes.NetWorker)

local run_service = game:GetService("RunService")
local http_service = game:GetService("HttpService")
local players = game:GetService("Players")

local is_server = run_service:IsServer()
local network_mode = if is_server then network.Server else network.Client

local function generate_guid()
	return http_service:GenerateGUID(false)
end

local request_require = network_mode:RemoteFunction('RequireEvent')
local request_token = network_mode:RemoteFunction('TokenEvent')
local adjust_player_tokens = network_mode:RemoteEvent('AdjustTokensEvent')

local require_calls_per_player = {
	test = 2,
	test2 = 4
}

local tokens_per_event = {
	test = 1,
	test2 = 2
}
module.remote_references = {}
module.EventTypes = {
	RemoteEvent = "RemoteEvent",
	UnreliableRemoteEvent = "UnreliableRemoteEvent",
	BindableEvent = "BindableEvent",
}
module.FunctionTypes = {
	RemoteFunction = "RemoteFunction",
	BindableFunction = "BindableFunction",
}

function module:Event(type_of_event : string, personal_name : string)
	if not type_of_event or not personal_name then return end

	if is_server then
		local existing_reference = module.remote_references[personal_name]
		if existing_reference then
			return existing_reference.event
		end

		local coded_name = generate_guid()
		local event = network_mode[type_of_event](nil, coded_name)	
		module.remote_references[personal_name] = {
			event = event,
			require_calls = require_calls_per_player[personal_name],
			coded_name = coded_name,
		}
		
		return event
	else
		local coded_name, maxed = request_require:Invoke(personal_name)
		if maxed == nil then
			return
		end
		
		local event = network_mode[type_of_event](nil, coded_name)
		if maxed then
			event.remote.Name = '1010used1010'
			event.remote.Parent = nil
		end
		
		return event
	end
end

-- for client
local token_methods = {}
token_methods.__index = token_methods

local token_player_data = {}

local function rotate_token(old : string, new : string)
	local token_data = token_player_data[old]
	if not token_data then
		return
	end
	if not token_data.used then
		return -- dont rotate, maybe have already been rotated due to order between Wait and Connect
	end

	token_player_data[old] = nil

	token_data.param_token = new
	token_data.used = false
	token_player_data[new] = token_data
end

function module:CreateParamToken(personal_name : string, ...:any): {param_token : string}
	if is_server then return end
	
	local name = request_token:Invoke(personal_name, ...)
	if not name then
		return
	end
	
	local token_data = setmetatable({
		param_token = name,
		used = false
	}, token_methods)
	token_player_data[name] = token_data
	return token_data
end

function token_methods:Use(timeout : number)
	local started = os.clock()

	while self.used do
		if timeout and os.clock() - started > timeout then
			return nil
		end

		task.wait()
	end

	self.used = true
	return self.param_token
end

-- for server
local player_info_cache = {}

function module:GetParams(player : Player, token : string, personal_name : string): {any}
	if not is_server then return end
	if typeof(token) ~= "string" then return end
	if typeof(personal_name) ~= "string" then return end
	
	local player_info = player_info_cache[player]
	if not player_info then return end
	
	local event_to_player = player_info[personal_name]
	if not event_to_player then return end
	
	local params = event_to_player.tokens[token]	
	if not params then return end
	
	local new_token = generate_guid()
	
	event_to_player.tokens[token] = nil
	event_to_player.tokens[new_token] = params
	
	adjust_player_tokens:Fire({false, player}, token, new_token)
	
	return params
end


local function create_player_info(player, personal_name)
	local player_info = player_info_cache[player]
	if not player_info then
		player_info = {}
		player_info_cache[player] = player_info
	end

	local event_info = player_info[personal_name]
	if not event_info then
		event_info = {
			require_calls = 0,
			tokens = {},
			token_count = 0,
		}
		player_info[personal_name] = event_info
	end

	return event_info
end

if is_server then	
	request_require:OnInvoke(function(player : Player, personal_name : string)	
		if typeof(personal_name) ~= 'string' then return end
		local require_call_limit = require_calls_per_player[personal_name]
		if not require_call_limit then return end

		local remote_reference = module.remote_references[personal_name]
		if not remote_reference then return end
		
		local event_info = create_player_info(player, personal_name)
		
		if event_info.require_calls < require_call_limit then
			event_info.require_calls += 1
			
			return remote_reference.coded_name, event_info.require_calls == require_call_limit
		else
			player:Kick('Somthing went wrong')
		end
	end)
	
	request_token:OnInvoke(function(player, personal_name : string, ...)
		if typeof(personal_name) ~= "string" then return end
		
		if not require_calls_per_player[personal_name] then
			return
		end
		if not module.remote_references[personal_name] then
			return
		end
		local token_limit = tokens_per_event[personal_name]
		if not token_limit then
			return
		end
		
		local event_info = create_player_info(player, personal_name)
		
		local token_name = generate_guid()
		if event_info.token_count < token_limit then
			event_info.tokens[token_name] = table.pack(...)
			event_info.token_count += 1
		else
			player:Kick('Somthing went wrong')
			return
		end
		
		return token_name
	end)
	
	players.PlayerRemoving:Connect(function(player)
		player_info_cache[player] = nil
	end)
end

if not is_server then
	adjust_player_tokens:Connect(function(old : string, new : string)
		rotate_token(old, new)
	end)
end

return module
