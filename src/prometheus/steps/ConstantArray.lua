local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Parser = require("prometheus.parser")
local enums = require("prometheus.enums")

local LuaVersion = enums.LuaVersion
local AstKind = Ast.AstKind

local ConstantArray = Step:extend()
ConstantArray.Description = "This Step will Extract all Constants and put them into an Array at the beginning of the script"
ConstantArray.Name = "Constant Array"

ConstantArray.SettingsDescriptor = {
	Treshold = { type = "number", default = 1, min = 0, max = 1 },
	StringsOnly = { type = "boolean", default = false },
	Shuffle = { type = "boolean", default = true },
	Rotate = { type = "boolean", default = true },
	LocalWrapperTreshold = { type = "number", default = 1, min = 0, max = 1 },
	LocalWrapperCount = { type = "number", default = 0, min = 0, max = 512 },
	LocalWrapperArgCount = { type = "number", default = 10, min = 1, max = 200 },
	MaxWrapperOffset = { type = "number", default = 65535, min = 0 },
	Encoding = {
		type = "enum",
		default = "base64",
		values = { "none", "base64" }
	}
}

function ConstantArray:init(settings)
	if type(settings) ~= "table" then
		settings = {}
	end
	for k, v in pairs(self.SettingsDescriptor) do
		if settings[k] == nil then
			self[k] = v.default
		else
			self[k] = settings[k]
		end
	end
end

function ConstantArray:createArray()
	local entries = {}
	for i, v in ipairs(self.constants) do
		if type(v) == "string" then
			v = self:encode(v)
		end
		entries[i] = Ast.TableEntry(Ast.ConstantNode(v))
	end
	return Ast.TableConstructorExpression(entries)
end

function ConstantArray:indexing(index, data)
	data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId)
	return Ast.FunctionCallExpression(
		Ast.VariableExpression(self.rootScope, self.wrapperId),
		{ Ast.NumberExpression(index) }
	)
end

function ConstantArray:getConstant(value, data)
	local idx = self.lookup[value]
	if not idx then
		idx = #self.constants + 1
		self.constants[idx] = value
		self.lookup[value] = idx
	end
	return self:indexing(idx, data)
end

function ConstantArray:encode(str)
	if self.Encoding ~= "base64" then
		return str
	end
	return ((str:gsub(".", function(x)
		local r = ""
		local b = x.byte(x)
		for i = 8, 1, -1 do
			r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
		end
		return r
	end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
		if #x < 6 then return "" end
		local c = 0
		for i = 1, 6 do
			c = c + (x.sub(x, i, i) == "1" and 2 ^ (6 - i) or 0)
		end
		return self.base64chars.sub(self.base64chars, c +c + 1, c + 1)
	end) .. ({ "", "==", "=" })[#str % 3 + 1])
end

function ConstantArray:apply(ast, pipeline)
	self.rootScope = ast.body.scope
	self.arrId = self.rootScope:addVariable()
	self.wrapperId = self.rootScope:addVariable()
	self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset)

	self.constants = {}
	self.lookup = {}

	self.base64chars = table.concat(util.shuffle({
		"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P",
		"Q","R","S","T","U","V","W","X","Y","Z",
		"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p",
		"q","r","s","t","u","v","w","x","y","z",
		"0","1","2","3","4","5","6","7","8","9","+","/"
	}))

	visitast(ast, nil, function(node, data)
		if math.random() <= self.Treshold then
			if node.kind == AstKind.StringExpression then
				self:addConstant(node.value)
				node.__ca = true
			elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
				self:addConstant(node.value)
				node.__ca = true
			end
		end
	end, function(node, data)
		if node.__ca then
			node.__ca = nil
			return self:getConstant(node.value, data)
		end
	end)

	if self.Shuffle then
		self.constants = util.shuffle(self.constants)
		self.lookup = {}
		for i, v in ipairs(self.constants) do
			self.lookup[v] = i
		end
	end

	table.insert(ast.body.statements, 1,
		Ast.LocalVariableDeclaration(
			self.rootScope,
			{ self.arrId },
			{ self:createArray() }
		)
	)

	local funcScope = Scope:new(self.rootScope)
	local arg = funcScope:addVariable()

	funcScope:addReferenceToHigherScope(self.rootScope, self.arrId)

	local indexExpr
	if self.wrapperOffset < 0 then
		indexExpr = Ast.SubExpression(
			Ast.VariableExpression(funcScope, arg),
			Ast.NumberExpression(-self.wrapperOffset)
		)
	else
		indexExpr = Ast.AddExpression(
			Ast.VariableExpression(funcScope, arg),
			Ast.NumberExpression(self.wrapperOffset)
		)
	end

	table.insert(ast.body.statements, 1,
		Ast.LocalFunctionDeclaration(
			self.rootScope,
			self.wrapperId,
			{ Ast.VariableExpression(funcScope, arg) },
			Ast.Block({
				Ast.ReturnStatement({
					Ast.IndexExpression(
						Ast.VariableExpression(self.rootScope, self.arrId),
						indexExpr
					)
				})
			}, funcScope)
		)
	)

	local proxyCode = [[
	do
		local raw = ARR
		setmetatable(raw, {
			__index = function(t, k)
				return raw[k + OFFSET]
			end
		})
	end
	]]

	local parser = Parser:new({ LuaVersion = LuaVersion.Lua51 })
	local proxyAst = parser:parse(
		proxyCode
			:gsub("ARR", self.rootScope:getVariableName(self.arrId))
			:gsub("OFFSET", tostring(self.wrapperOffset))
	)

	local stat = proxyAst.body.statements[1]
	stat.body.scope:setParent(ast.body.scope)
	table.insert(ast.body.statements, 1, stat)

	self.rootScope = nil
	self.arrId = nil
	self.wrapperId = nil
	self.constants = nil
	self.lookup = nil
end

return ConstantArray
