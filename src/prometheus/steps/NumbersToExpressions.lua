-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua - Strengthened & Compatible
-- Fixed: Uses BinaryExpression and PrefixExpression for maximum compatibility.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Converts numbers into complex mathematical trees using universal AST constructors."
NumbersToExpressions.Name = "Numbers To Expressions (Compatible)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1, min = 0, max = 1 },
    InternalTreshold = { type = "number", default = 0.5, min = 0, max = 0.8 },
    MaxDepth = { type = "number", default = 4, min = 1, max = 15 }
}

local function is_int(n)
    return n == math.floor(n)
end

function NumbersToExpressions:init(settings)
    self.ExpressionGenerators = {
        -- 1. Addition
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.BinaryExpression(self:CreateNumberExpression(r, depth), self:CreateNumberExpression(val - r, depth), "+")
        end,

        -- 2. Subtraction
        function(val, depth)
            local r = math.random(-1000, 1000)
            return Ast.BinaryExpression(self:CreateNumberExpression(val + r, depth), self:CreateNumberExpression(r, depth), "-")
        end,

        -- 3. Multiplication
        function(val, depth)
            if val == 0 then return false end
            local factor = math.random(2, 5)
            if is_int(val / factor) then
                return Ast.BinaryExpression(self:CreateNumberExpression(factor, depth), self:CreateNumberExpression(val / factor, depth), "*")
            end
            return false
        end,

        -- 4. Division
        function(val, depth)
            local factor = math.random(2, 5)
            return Ast.BinaryExpression(self:CreateNumberExpression(val * factor, depth), self:CreateNumberExpression(factor, depth), "/")
        end,

        -- 5. Control Flow Flattening (Ternary Logic)
        function(val, depth)
            local junk = math.random(-5000, 5000)
            local cond_val = math.random(1, 100)
            
            local condition = Ast.BinaryExpression(
                self:CreateNumberExpression(cond_val, depth),
                self:CreateNumberExpression(cond_val, depth),
                "=="
            )

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
        
        -- 6. Prefix/Unary Negation (Fixed: PrefixExpression)
        function(val, depth)
            -- If PrefixExpression fails, it falls back to Binary (0 - val)
            local op = Ast.PrefixExpression or Ast.UnaryExpression
            if op then
                return op("-", Ast.ParenthesisExpression(
                    op("-", self:CreateNumberExpression(val, depth))
                ))
            else
                return Ast.BinaryExpression(self:CreateNumberExpression(0, depth), self:CreateNumberExpression(val, depth), "-")
            end
        end
    }
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    if depth > self.MaxDepth or (depth > 0 and math.random() >= self.InternalTreshold) then
        local node = Ast.NumberExpression(val)
        node.NoObfuscation = true
        return node
    end

    local generators = util.shuffle({table.unpack(self.ExpressionGenerators)})
    for _, generator in ipairs(generators) do
        local node = generator(val, depth + 1)
        if node then return node end
    end

    local node = Ast.NumberExpression(val)
    node.NoObfuscation = true
    return node
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0)
            end
        end
    end)
end

return NumbersToExpressions
