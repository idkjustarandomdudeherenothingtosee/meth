-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua - Extreme Expression Obfuscation
-- Cleaned of UTF-8 encoding errors (\194).

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
    MaxDepth = { type = "number", default = 6, min = 1, max = 15 }
}

-- Helper to ensure we don't break the script with floats where integers are expected
local function is_int(n)
    return n == math.floor(n)
end

function NumbersToExpressions:init(settings)
    self.ExpressionGenerators = {
        -- Addition logic: x = (a + b)
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.AddExpression(self:CreateNumberExpression(r, depth), self:CreateNumberExpression(val - r, depth), false)
        end,

        -- Subtraction logic: x = (a - b)
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.SubExpression(self:CreateNumberExpression(val + r, depth), self:CreateNumberExpression(r, depth), false)
        end,

        -- Multiplication logic: x = (a * b)
        function(val, depth)
            if val == 0 then return false end
            local factor = math.random(2, 5)
            if is_int(val / factor) then
                return Ast.MulExpression(self:CreateNumberExpression(factor, depth), self:CreateNumberExpression(val / factor, depth), false)
            end
            return false
        end,

        -- Division logic: x = (a / b)
        function(val, depth)
            local factor = math.random(2, 5)
            return Ast.DivExpression(self:CreateNumberExpression(val * factor, depth), self:CreateNumberExpression(factor, depth), false)
        end,

        -- Logical Control Flow Flattening (The "Fake Branch")
        -- val = ((condition and val or junk) + 0)
        function(val, depth)
            local junk = math.random(-5000, 5000)
            local cond_val = math.random(1, 100)
            
            -- Create: ( (cond_val == cond_val) and val or junk )
            local condition = Ast.EqualityExpression(
                self:CreateNumberExpression(cond_val, depth),
                self:CreateNumberExpression(cond_val, depth),
                "=="
            )

            return Ast.LogicalOrExpression(
                Ast.LogicalAndExpression(
                    Ast.ParenthesisExpression(condition),
                    self:CreateNumberExpression(val, depth)
                ),
                self:CreateNumberExpression(junk, depth)
            )
        end,
        
        -- Unary Negation Logic: x = -(-x)
        function(val, depth)
            return Ast.UnaryExpression("-", Ast.ParenthesisExpression(
                Ast.UnaryExpression("-", self:CreateNumberExpression(val, depth))
            ))
        end
    }
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    -- Safety checks and recursion depth limits
    if depth > self.MaxDepth or (depth > 0 and math.random() >= self.InternalTreshold) then
        local node = Ast.NumberExpression(val)
        node.NoObfuscation = true -- Prevent infinite loops
        return node
    end

    local generators = util.shuffle({table.unpack(self.ExpressionGenerators)})
    for _, generator in ipairs(generators) do
        local node = generator(val, depth + 1)
        if node then return node end
    end

    return Ast.NumberExpression(val)
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node, data)
        -- Important: Do not re-obfuscate numbers we generated or numbers marked safe
        if node.kind == AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0)
            end
        end
    end)
end

return NumbersToExpressions
