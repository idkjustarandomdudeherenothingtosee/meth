-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua
--
-- This Script provides an Obfuscation Step, that converts Number Literals to expressions
unpack = unpack or table.unpack;

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")

local AstKind = Ast.AstKind;

local NumbersToExpressions = Step:extend();
NumbersToExpressions.Description = "This Step Converts number Literals to Expressions";
NumbersToExpressions.Name = "Numbers To Expressions";

NumbersToExpressions.SettingsDescriptor = {
	Treshold = {
        type = "number",
        default = 1,
        min = 0,
        max = 1,
    },
    InternalTreshold = {
        type = "number",
        default = 0.2,
        min = 0,
        max = 0.8,
    }
}

function NumbersToExpressions:init(settings)
	self.ExpressionGenerators = {
    function(val, depth)
        local a = math.random(-2^20, 2^20)
        local b = val - a
        if tonumber(tostring(a + b)) ~= val then
            return false
        end
        return Ast.AddExpression(self:CreateNumberExpression(a, depth + 1), self:CreateNumberExpression(b, depth + 1), false)
    end,
    function(val, depth)
        local a = math.random(-2^20, 2^20)
        local b = val + a
        if tonumber(tostring(b - a)) ~= val then
            return false
        end
        return Ast.SubExpression(self:CreateNumberExpression(b, depth + 1), self:CreateNumberExpression(a, depth + 1), false)
    end,
    function(val, depth)
        local a = math.random(1, 2^10)
        local b = val / a
        if b % 1 ~= 0 then
            return false
        end
        if tonumber(tostring(b * a)) ~= val then
            return false
        end
        return Ast.MulExpression(self:CreateNumberExpression(b, depth + 1), self:CreateNumberExpression(a, depth + 1), false)
    end,
    function(val, depth)
        local a = math.random(1, 2^10)
        local b = val * a
        if tonumber(tostring(b / a)) ~= val then
            return false
        end
        return Ast.DivExpression(self:CreateNumberExpression(b, depth + 1), self:CreateNumberExpression(a, depth + 1), false)
    end,
    function(val, depth)
        local a = math.random(0, 2^20)
        local b = bit32.bxor(val, a)
        if bit32.bxor(b, a) ~= val then
            return false
        end
        return Ast.BxorExpression(self:CreateNumberExpression(b, depth + 1), self:CreateNumberExpression(a, depth + 1))
    end,
    function(val, depth)
        local a = math.random(1, 2^10)
        local b = -val + a
        if tonumber(tostring(-(b - a))) ~= val then
            return false
        end
        return Ast.UnaryMinusExpression(
            Ast.SubExpression(self:CreateNumberExpression(b, depth + 1), self:CreateNumberExpression(a, depth + 1), false)
        )
    end,
    function(val, depth)
        local a = math.random(1, 2^10)
        local b = math.random(1, 2^10)
        local c = val + a - b
        if tonumber(tostring(c - a + b)) ~= val then
            return false
        end
        return Ast.SubExpression(
            Ast.AddExpression(self:CreateNumberExpression(c, depth + 1), self:CreateNumberExpression(b, depth + 1), false),
            self:CreateNumberExpression(a, depth + 1),
            false
        )
    end
}

end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    if depth > 0 and math.random() >= self.InternalTreshold or depth > 15 then
        return Ast.NumberExpression(val)
    end

    local generators = util.shuffle({unpack(self.ExpressionGenerators)});
    for i, generator in ipairs(generators) do
        local node = generator(val, depth + 1);
        if node then
            return node;
        end
    end

    return Ast.NumberExpression(val)
end

function NumbersToExpressions:apply(ast)
	visitast(ast, nil, function(node, data)
        if node.kind == AstKind.NumberExpression then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0);
            end
        end
    end)
end

return NumbersToExpressions;
