-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua - Extreme Expression Obfuscation
-- Fixed: Replaced EqualityExpression with BinaryExpression for compatibility.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Converts numbers into deep, non-linear mathematical and logical decision trees."
NumbersToExpressions.Name = "Numbers To Expressions (Extreme)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1, min = 0, max = 1 },
    InternalTreshold = { type = "number", default = 0.5, min = 0, max = 0.8 },
    MaxDepth = { type = "number", default = 5, min = 1, max = 15 }
}

-- Helper to ensure integer safety for multiplication/division
local function is_int(n)
    return n == math.floor(n)
end

function NumbersToExpressions:init(settings)
    self.ExpressionGenerators = {
        -- 1. Addition: x = (a + b)
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.AddExpression(self:CreateNumberExpression(r, depth), self:CreateNumberExpression(val - r, depth), false)
        end,

        -- 2. Subtraction: x = (a - b)
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.SubExpression(self:CreateNumberExpression(val + r, depth), self:CreateNumberExpression(r, depth), false)
        end,

        -- 3. Multiplication: x = (a * b)
        function(val, depth)
            if val == 0 then return false end
            local factor = math.random(2, 5)
            if is_int(val / factor) then
                return Ast.MulExpression(self:CreateNumberExpression(factor, depth), self:CreateNumberExpression(val / factor, depth), false)
            end
            return false
        end,

        -- 4. Division: x = (a / b)
        function(val, depth)
            local factor = math.random(2, 5)
            return Ast.DivExpression(self:CreateNumberExpression(val * factor, depth), self:CreateNumberExpression(factor, depth), false)
        end,

        -- 5. Logical "Flattening" (The Fake Branch)
        -- result = ((condition and val or junk))
        function(val, depth)
            local junk = math.random(-5000, 5000)
            local cond_val = math.random(1, 100)
            
            -- Always True Condition: (cond_val == cond_val)
            local condition = Ast.BinaryExpression(
                self:CreateNumberExpression(cond_val, depth),
                self:CreateNumberExpression(cond_val, depth),
                "=="
            )

            -- Expression: ( (condition) and val or junk )
            return Ast.BinaryExpression(
                Ast.BinaryExpression(
                    Ast.ParenthesisExpression(condition),
                    self:CreateNumberExpression(val, depth),
                    "and"
                ),
                self:CreateNumberExpression(junk, depth),
                "or"
            )
        end,
        
        -- 6. Unary Negation: x = -(-x)
        function(val, depth)
            return Ast.UnaryExpression("-", Ast.ParenthesisExpression(
                Ast.UnaryExpression("-", self:CreateNumberExpression(val, depth))
            ))
        end
    }
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    -- Stop recursion based on depth or probability
    if depth > self.MaxDepth or (depth > 0 and math.random() >= self.InternalTreshold) then
        local node = Ast.NumberExpression(val)
        node.NoObfuscation = true -- Flag to prevent the visitor from re-processing this node
        return node
    end

    local generators = util.shuffle({table.unpack(self.ExpressionGenerators)})
    for _, generator in ipairs(generators) do
        local node = generator(val, depth + 1)
        if node then return node end
    end

    -- Fallback
    local node = Ast.NumberExpression(val)
    node.NoObfuscation = true
    return node
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node, data)
        -- Skip numbers marked safe (from ConstantArray) or numbers we already transformed
        if node.kind == AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0)
            end
        end
    end)
end

return NumbersToExpressions
