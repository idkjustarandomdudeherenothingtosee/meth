local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local RandomStrings = require("prometheus.randomStrings")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local logger = require("logger")

local AntiTamper = Step.extend()

AntiTamper.Description = "This Step Breaks your Script when it is modified. This is only effective when using the new VM."
AntiTamper.Name = "Anti Tamper"

AntiTamper.SettingsDescriptor = {
	UseDebug = {
		type = "boolean",
		default = true,
		description = "Use debug library. (Recommended, however scripts will not work without debug library.)"
	}
}

function AntiTamper:init(settings)
	if type(settings) ~= "table" then
		settings = {}
	end

	local ud = settings.UseDebug
	if ud == nil then
		ud = AntiTamper.SettingsDescriptor.UseDebug.default
	end

	self.UseDebug = ud == true
end

function AntiTamper:apply(ast, pipeline)
	if not ast or not ast.body or not ast.body.statements then
		return ast
	end

	if not pipeline then
		pipeline = {}
	end

	if pipeline.PrettyPrint then
		logger:warn(string.format("\"%s\" cannot be used with PrettyPrint, ignoring \"%s\"", self.Name, self.Name))
		return ast
	end

	if ast.__antitamper_applied then
		return ast
	end
	ast.__antitamper_applied = true

	local seed = RandomStrings.randomString()
	local guard = RandomStrings.randomString()

	local code = [[
do
	local valid = true
	local ]] .. guard .. [[ = true

	if _G and _G.]] .. guard .. [[ then
		error("reentry")
	end
	if _G then
		_G.]] .. guard .. [[ = true
	end

	local function kill()
		while true do
			error("Tamper Detected!")
		end
	end
]]

	if self.UseDebug then
		code = code .. [[
		local dbg = debug
		if not dbg then
			valid = false
		else
			local sethook = dbg.sethook or function() end
			local calls = 0
			local line = nil

			sethook(function(_, l)
				if not l then return end
				calls = calls + 1
				if line and l ~= line then
					sethook(kill, "l", 1)
				else
					line = l
				end
			end, "l", 1)

			(function() end)()
			(function() end)()
			sethook()

			if calls < 2 then
				valid = false
			end

			local funcs = {pcall, tostring, string.char, dbg.getinfo}
			for i = 1, #funcs do
				local info = dbg.getinfo(funcs[i])
				if not info or info.what ~= "C" then
					valid = false
				end
				if dbg.getupvalue(funcs[i], 1) then
					valid = false
				end
				if dbg.getlocal(funcs[i], 1) then
					valid = false
				end
			end
		end
]]
	end

	code = code .. [[
	local pcall_ok = false
	local ok = pcall(function()
		pcall_ok = true
	end)
	valid = valid and ok and pcall_ok

	local r = math.random
	local gmatch = string.gmatch
	local unpackv = table.unpack or unpack

	local a1, a2 = 0, 0
	local rounds = r(8, 32)

	local errpack = {pcall(function()
		local x = ]] .. tostring(math.random(1, 2^24)) .. [[ - "]] .. seed .. [[" ^ ]] .. tostring(math.random(1, 2^24)) .. [[
		return "]] .. seed .. [[" / x
	end)}

	local msg = errpack[2]
	if type(msg) ~= "string" then
		valid = false
	end

	local baseLine = tonumber(gmatch(msg, ":(%d*):")())

	for i = 1, rounds do
		local len = r(5, 50)
		local idx = r(1, len)
		local v = r(0, 255)

		local arr = {pcall(function()
			local t = {}
			for j = 1, len do
				t[j] = r(0, 255)
			end
			t[idx] = v
			return unpackv(t)
		end)}

		if not arr[1] then
			valid = false
		else
			a1 = (a1 + arr[idx + 1]) % 256
			a2 = (a2 + v) % 256
		end
	end

	valid = valid and a1 == a2

	if not valid then
		kill()
	end
end
]]

	local parser = Parser.new({ LuaVersion = Enums.LuaVersion.Lua51 })
	local parsed = parser:parse(code)

	if not parsed or not parsed.body or not parsed.body.statements then
		return ast
	end

	local doStat = parsed.body.statements[1]
	if not doStat or not doStat.body or not doStat.body.scope then
		return ast
	end

	if ast.body.scope and doStat.body.scope.setParent then
		doStat.body.scope:setParent(ast.body.scope)
	end

	table.insert(ast.body.statements, 1, doStat)

	return ast
end

return AntiTamper
