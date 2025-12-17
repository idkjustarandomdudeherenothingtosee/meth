-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua - Strengthened with CFF logic and Multi-Op support
--

unpack = unpack or table.unpack;

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")

local AstKind = Ast.AstKind;

local NumbersToExpressions = Step:extend();
NumbersToExpressions.Description = "Converts numbers into deep, non-linear mathematical and logical expressions.";
NumbersToExpressions.Name = "Numbers To Expressions (Strengthened)";

NumbersToExpressions.SettingsDescriptor = {
	Treshold = { type = "number", default = 1, min = 0, max = 1 },
	InternalTreshold = { type = "number", default = 0.4, min = 0, max = 0.8 },
    MaxDepth = { type = "number", default = 5, min = 1, max = 15 }
}

function NumbersToExpressions:init(settings)
    -- Complex Expression Generators
	self.ExpressionGenerators = {
        -- Addition: x = a + b
        function(val, depth) 
            local val2 = math.random(-10000, 10000);
            local diff = val - val2;
            return Ast.AddExpression(self:CreateNumberExpression(val2, depth), self:CreateNumberExpression(diff, depth), false);
        end, 

        -- Subtraction: x = a - b
        function(val, depth)
            local val2 = math.random(-10000, 10000);
            local diff = val + val2;
            return Ast.SubExpression(self:CreateNumberExpression(diff, depth), self:CreateNumberExpression(val2, depth), false);
        end,

        -- Multiplication: x = (a * b)
        function(val, depth)
            if val == 0 then return false end
            local factors = {2, 3, 4, 5, 10, 20}
            local factor = factors[math.random(#factors)]
            local other = val / factor
            -- Ensure we don't create nasty float precision issues for integers
            if math.floor(other) ~= other then return false end 
            return Ast.MulExpression(self:CreateNumberExpression(factor, depth), self:CreateNumberExpression(other, depth), false)
        end,

        -- Division: x = (a / b)
        function(val, depth)
            local factor = math.random(2, 10)
            local product = val * factor
            return Ast.DivExpression(self:CreateNumberExpression(product, depth), self:CreateNumberExpression(factor, depth), false)
        end,

        -- Logical Flattening (Ternary): x = (true and x or fake)
        function(val, depth)
            local fakeVal = math.random(-10000, 10000)
            -- Represents: ( (1 == 1) and val or fakeVal )
            return Ast.LogicalAndExpression(
                Ast.LogicalOrExpression(
                    Ast.ParenthesisExpression(
                        Ast.EqualityExpression(self:CreateNumberExpression(1, depth), self:CreateNumberExpression(1, depth), "==")
                    ),
                    self:CreateNumberExpression(val, depth)
                ),
                self:CreateNumberExpression(val, depth)
            )
        end
    }
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    -- Stop recursion if depth limit reached or random roll fails
    if depth > self.MaxDepth or (depth > 0 and math.random() >= self.InternalTreshold) then
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
        -- SAFETY: Skip numbers marked for no obfuscation (crucial for ConstantArray safety)
        if node.NoObfuscation or node.IsGenerated then
            return nil
        end

        if node.kind == AstKind.NumberExpression then
            if math.random() <= self.Treshold then
                -- Convert literal number to a nested tree of math
                local newNode = self:CreateNumberExpression(node.value, 0);
                return newNode
            end
      0 end
    end)
end

return NumbersToExpressions;
