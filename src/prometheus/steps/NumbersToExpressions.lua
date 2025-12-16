unpack = unpack or table.unpack

local step = require("prometheus.step")
local ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")

local astkind = ast.AstKind

local numberstoexpressions = step:extend()
numberstoexpressions.description = "numbers to expressions"
numberstoexpressions.name = "numbers to expressions"

numberstoexpressions.settingsdescriptor = {
	Treshold = { type = "number", default = 1, min = 0, max = 1 },
	InternalTreshold = { type = "number", default = 0.15, min = 0, max = 0.9 },
	MaxDepth = { type = "number", default = 25, min = 5, max = 60 }
}

local function safeeq(a, b)
	return tonumber(tostring(a)) == tonumber(tostring(b))
end

function numberstoexpressions:init(settings)
	self.treshold = settings.Treshold or 1
	self.internaltreshold = settings.InternalTreshold or 0.15
	self.maxdepth = settings.MaxDepth or 25

	self.generators = {
		function(val, depth)
			local a = math.random(-2^20, 2^20)
			local b = val - a
			if not safeeq(a + b, val) then return false end
			return ast.AddExpression(self:create(a, depth), self:create(b, depth), false)
		end,
		function(val, depth)
			local a = math.random(-2^20, 2^20)
			local b = val + a
			if not safeeq(b - a, val) then return false end
			return ast.SubExpression(self:create(b, depth), self:create(a, depth), false)
		end,
		function(val, depth)
			if val == 0 then return false end
			local m = math.random(1, 25)
			local a = val * m
			if not safeeq(a / m, val) then return false end
			return ast.DivExpression(self:create(a, depth), self:create(m, depth), false)
		end,
		function(val, depth)
			local m = math.random(1, 25)
			local a = val / m
			if not safeeq(a * m, val) then return false end
			return ast.MulExpression(self:create(a, depth), self:create(m, depth), false)
		end,
		function(val, depth)
			return ast.UnaryExpression("-", ast.UnaryExpression("-", self:create(val, depth), false), false)
		end,
		function(val, depth)
			local a = math.random(-100000, 100000)
			local b = math.random(-100000, 100000)
			local c = val - a - b
			if not safeeq(a + b + c, val) then return false end
			return ast.AddExpression(
				ast.AddExpression(self:create(a, depth), self:create(b, depth), false),
				self:create(c, depth),
				false
			)
		end,
		function(val, depth)
			local z = math.random(-50000, 50000)
			if not safeeq(val + z - z, val) then return false end
			return ast.SubExpression(
				ast.AddExpression(self:create(val, depth), self:create(z, depth), false),
				self:create(z, depth),
				false
			)
		end,
		function(val, depth)
			return ast.MulExpression(self:create(val, depth), self:create(1, depth), false)
		end,
		function(val, depth)
			return ast.AddExpression(self:create(val, depth), self:create(0, depth), false)
		end
	}
end

function numberstoexpressions:create(val, depth)
	if depth >= self.maxdepth or (depth > 0 and math.random() >= self.internaltreshold) then
		return ast.NumberExpression(val)
	end

	local gens = util.shuffle({ unpack(self.generators) })
	for i = 1, #gens do
		local node = gens[i](val, depth + 1)
		if node then
			if math.random() < 0.35 then
				return self:wrap(node, depth + 1)
			end
			return node
		end
	end

	return ast.NumberExpression(val)
end

function numberstoexpressions:wrap(node, depth)
	if depth >= self.maxdepth then
		return node
	end

	local z = math.random(-1000, 1000)

	if math.random() < 0.5 then
		return ast.AddExpression(
			ast.SubExpression(node, self:create(z, depth), false),
			self:create(z, depth),
			false
		)
	end

	return ast.SubExpression(
		ast.AddExpression(node, self:create(z, depth), false),
		self:create(z, depth),
		false
	)
end

function numberstoexpressions:apply(asttree)
	visitast(asttree, nil, function(node)
		if node.kind == astkind.NumberExpression then
			if math.random() <= self.treshold then
				return self:create(node.value, 0)
			end
		end
	end)
end

return numberstoexpressions
