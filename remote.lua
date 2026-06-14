local M={}
local N=require(script.Parent.Remotes.NetWorker)
local R=game:GetService("RunService")
local H=game:GetService("HttpService")
local P=game:GetService("Players")
local S=R:IsServer()
local X=if S then N.Server else N.Client
local function G()return H:GenerateGUID(false)end
local Q=X:RemoteFunction("RequireEvent")
local T=X:RemoteFunction("TokenEvent")
local A=X:RemoteEvent("AdjustTokensEvent")
local L={test=2,test2=4}
local C={test=1,test2=2}
local D={}
local K={}
local V={}
local Y={}
K.__index=K
M.remote_references=V
M.EventTypes={RemoteEvent="RemoteEvent",UnreliableRemoteEvent="UnreliableRemoteEvent",BindableEvent="BindableEvent"}
M.FunctionTypes={RemoteFunction="RemoteFunction",BindableFunction="BindableFunction"}
function M:Event(a,b)
	if not a or not b then return end
	if S then
		local c=V[b]
		if c then return c.event end
		local d=G()
		local e=X[a](nil,d)
		V[b]={event=e,require_calls=L[b],coded_name=d}
		return e
	end
	local c,d=Q:Invoke(b)
	if d==nil then return end
	local e=X[a](nil,c)
	if d then e.remote.Name="1010used1010" e.remote.Parent=nil end
	return e
end
local function Z(a,b)
	local c=Y[a]
	if not c or not c.used then return end
	Y[a]=nil
	c.param_token=b
	c.used=false
	Y[b]=c
end
function M:CreateParamToken(a,...:any):{param_token:string}
	if S then return end
	local b=T:Invoke(a,...)
	if not b then return end
	local c=setmetatable({param_token=b,used=false},K)
	Y[b]=c
	return c
end
function K:Use(a:number)
	local b=os.clock()
	while self.used do
		if a and os.clock()-b>a then return nil end
		task.wait()
	end
	self.used=true
	return self.param_token
end
function M:GetParams(a:Player,b:string,c:string):{any}
	if not S or typeof(b)~="string" or typeof(c)~="string" then return end
	local d=D[a]
	if not d then return end
	local e=d[c]
	if not e then return end
	local f=e.tokens[b]
	if not f then return end
	local g=G()
	e.tokens[b]=nil
	e.tokens[g]=f
	A:Fire({false,a},b,g)
	return f
end
local function W(a,b)
	local c=D[a]
	if not c then c={} D[a]=c end
	local d=c[b]
	if not d then d={require_calls=0,tokens={},token_count=0} c[b]=d end
	return d
end
if S then
	Q:OnInvoke(function(a:Player,b:string)
		if typeof(b)~="string" then return end
		local c=L[b]
		if not c then return end
		local d=V[b]
		if not d then return end
		local e=W(a,b)
		if e.require_calls<c then
			e.require_calls+=1
			return d.coded_name,e.require_calls==c
		end
		a:Kick("Somthing went wrong")
	end)
	T:OnInvoke(function(a,b:string,...)
		if typeof(b)~="string" or not L[b] or not V[b] then return end
		local c=C[b]
		if not c then return end
		local d=W(a,b)
		local e=G()
		if d.token_count<c then
			d.tokens[e]=table.pack(...)
			d.token_count+=1
		else
			a:Kick("Somthing went wrong")
			return
		end
		return e
	end)
	P.PlayerRemoving:Connect(function(a)D[a]=nil end)
else
	A:Connect(function(a:string,b:string)Z(a,b)end)
end
return M
