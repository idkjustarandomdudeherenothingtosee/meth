unpack = unpack or table.unpack

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local NumbersToExpressions = Step.extend()

NumbersToExpressions.Description = "This Step Converts number Literals to Expressions"
NumbersToExpressions.Name = "Numbers To Expressions"

NumbersToExpressions.SettingsDescriptor = {
	Treshold = {
		type = "number",
		default = 1,
		min = 0,
		max = 1
	},
	InternalTreshold = {
		type = "number",
		default = 0.2,
		min = 0,
		max = 0.8
	}
}

local function safeint(n)
	return tonumber(string.format("%.0f", n))
end

function NumbersToExpressions.init(self, settings)
	self.Treshold = settings.Treshold
	self.InternalTreshold = settings.InternalTreshold

	self.ExpressionGenerators = {
		function(val, depth)
			local v2 = safeint(math.random(-2^20, 2^20))
			local d = safeint(val - v2)
			if safeint(d + v2) ~= val then
				return false
			end
			return Ast.AddExpression(
				self.CreateNumberExpression(self, v2, depth),
				self.CreateNumberExpression(self, d, depth),
				false
			)
		end,

		function(val, depth)
			local v2 = safeint(math.random(-2^20, 2^20))
			local d = safeint(val + v2)
			if safeint(d - v2) ~= val then
				return false
			end
			return Ast.SubExpression(
				self.CreateNumberExpression(self, d, depth),
				self.CreateNumberExpression(self, v2, depth),
				false
			)
		end,

		function(val, depth)
			if val == 0 then
				return false
			end
			local m = safeint(math.random(1, 9))
			local p = safeint(val * m)
			if safeint(p / m) ~= val then
				return false
			end
			return Ast.DivExpression(
				self.CreateNumberExpression(self, p, depth),
				self.CreateNumberExpression(self, m, depth),
				false
			)
		end,

		function(val, depth)
			local m = safeint(math.random(1, 9))
			local d = safeint(val / m)
			if safeint(d * m) ~= val then
				return false
			end
			return Ast.MulExpression(
				self.CreateNumberExpression(self, d, depth),
				self.CreateNumberExpression(self, m, depth),
				false
			)
		end,

		function(val, depth)
			local n = safeint(-val)
			if safeint(-n) ~= val then
				return false
			end
			return Ast.UnaryExpression(
				"-",
				self.CreateNumberExpression(self, n, depth)
			)
		end
	}
end

function NumbersToExpressions.CreateNumberExpression(self, val, depth)
	if depth > 0 and math.random() >= self.InternalTreshold or depth > 18 then
		return Ast.NumberExpression(val)
	end

	local gens = util.shuffle({ unpack(self.ExpressionGenerators) })
	for _, gen in ipairs(gens) do
		local node = gen(val, depth + 1)
		if node then
			return node
		end
	end

	return Ast.NumberExpression(val)
end

function NumbersToExpressions.apply(self, ast)
	visitast(ast, nil, function(node)
		if node.kind == AstKind.NumberExpression then
			if math.random() <= self.Treshold then
				return self.CreateNumberExpression(self, node.value, 0)
			end
		end
	end)
end

return NumbersToExpressions
