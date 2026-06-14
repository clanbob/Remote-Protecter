local module = {}

local network = require(script.Parent.Remotes.NetWorker)

local run_service = game:GetService("RunService")
local http_service = game:GetService("HttpService")

local is_server = run_service:IsServer()
local network_mode = if is_server then network.Server else network.Client

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
local player_info_cach = {}


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
	
	local coded_name = http_service:GenerateGUID(false)
	if is_server then
		if module.remote_references[personal_name] then
			return module.remote_references[personal_name].event
		end
		
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
local tokens = {}
tokens.__index = tokens

local token_player_data = {}

local function rotate_token(old : string, new : string)
	local token_data = token_player_data[old]
	if not token_data then
		return
	end
	if token_data.used == false then
		return -- dont rotate, maybe have already been rotated due to order between Wait and Connect
	end

	token_player_data[old] = nil

	token_data.param_token = new
	token_player_data[new] = token_data
	
	token_data.used = false
end

function module:CreateParamToken(personal_name : string, ...:any): {param_token : string}
	if is_server then return end
	
	local name = request_token:Invoke(personal_name, ...)
	if not name then
		return
	end
	
	token_player_data[name] = setmetatable({
		param_token = name,
		used = false
	}, tokens)
	return token_player_data[name]
end

function tokens:Use(timeout : number)
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
function module:GetParams(player : Player, token : string, personal_name : string): {any}
	if not is_server then return end
	if typeof(token) ~= "string" then return end
	if typeof(personal_name) ~= "string" then return end
	
	local player_info = player_info_cach[player]
	if not player_info then return end
	
	local event_to_player = player_info[personal_name]
	if not event_to_player then return end
	
	local params = event_to_player.tokens[token]	
	if not params then return end
	
	local new_token = http_service:GenerateGUID(false)
	
	event_to_player.tokens[token] = nil
	event_to_player.tokens[new_token] = params
	
	adjust_player_tokens:Fire({false, player}, token, new_token)
	
	return params
end


local function create_player_info(player, personal_name)
	player_info_cach[player] = player_info_cach[player] or {}
	player_info_cach[player][personal_name] = player_info_cach[player][personal_name] or {
		require_calls = 0,
		tokens = {},
		token_count = 0,
	}
end

if is_server then	
	request_require:OnInvoke(function(player : Player, personal_name : string)	
		if typeof(personal_name) ~= 'string' then return end
		if not require_calls_per_player[personal_name] then return end
		if not module.remote_references[personal_name] then return end
		
		create_player_info(player, personal_name)
		
		if player_info_cach[player][personal_name].require_calls < require_calls_per_player[personal_name] then
			local cached_coded_name = module.remote_references[personal_name].coded_name
			player_info_cach[player][personal_name].require_calls += 1	
			
			return cached_coded_name, player_info_cach[player][personal_name].require_calls == require_calls_per_player[personal_name]
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
		if not tokens_per_event[personal_name] then
			return
		end
		
		create_player_info(player, personal_name)
		
		local token_name = http_service:GenerateGUID(false)
		if player_info_cach[player][personal_name].token_count < tokens_per_event[personal_name] then
			player_info_cach[player][personal_name].tokens[token_name] = table.pack(...)
			player_info_cach[player][personal_name].token_count += 1
		else
			player:Kick('Somthing went wrong')
			return
		end
		
		return token_name
	end)
	
	game.Players.PlayerRemoving:Connect(function(player)
		player_info_cach[player] = nil
	end)
end

if not is_server then
	adjust_player_tokens:Connect(function(old : string, new : string)
		rotate_token(old, new)
	end)
end

return module
