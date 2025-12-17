-- NumbersToExpressions.lua - Structure-Agnostic & Circular-Safe
local Step = require("prometheus.step")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Parser = require("prometheus.parser")
local Ast = require("prometheus.ast")

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Deeply obfuscates numbers using parser injection without circular recursion."
NumbersToExpressions.Name = "Numbers To Expressions (Safe)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1 },
    MaxDepth = { type = "number", default = 3 }
}

function NumbersToExpressions:init(settings)
    self.internalParser = Parser:new({ LuaVersion = "Lua51" })
end

-- Safely extracts the expression from a "local _ = math" statement 
-- without recursing into circular parent pointers.
local function extractExpression(tempAst)
    if not tempAst or not tempAst.body or not tempAst.body.statements then return nil end
    
    local stmt = tempAst.body.statements[1]
    if not stmt then return nil end
    
    -- In Prometheus, local declarations store values in 'init' or 'values' or 'expressions'
    -- We check the most common fields specifically to avoid recursion.
    local expr = (stmt.init and stmt.init[1]) or (stmt.values and stmt.values[1]) or (stmt.expressions and stmt.expressions[1])
    
    return expr
end

function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth or math.random() > 0.7 then
        -- Use string.format to ensure floats don't lose precision
        return tostring(val)
    end

    local op = math.random(1, 5)
    if op == 1 then -- Add
        local r = math.random(-50, 50)
        return string.format("(%s + %s)", self:GenerateMathString(r, depth + 1), self:GenerateMathString(val - r, depth + 1))
    elseif op == 2 then -- Sub
        local r = math.random(-50, 50)
        return string.format("(%s - %s)", self:GenerateMathString(val + r, depth + 1), self:GenerateMathString(r, depth + 1))
    elseif op == 3 and val ~= 0 and val % 2 == 0 then -- Mul
        return string.format("(%s * 2)", self:GenerateMathString(val / 2, depth + 1))
    elseif op == 4 then -- Div
        local r = math.random(2, 4)
        return string.format("(%s / %s)", self:GenerateMathString(val * r, depth + 1), r)
    else -- Logic
        local junk = math.random(1, 1000)
        return string.format("((1 == 1) and %s or %s)", self:GenerateMathString(val, depth + 1), junk)
    end
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        -- Only process literal numbers that aren't already flagged
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:GenerateMathString(node.value, 0)
                
                -- We wrap it in a local assignment because every Lua parser handles that consistently.
                local success, tempAst = pcall(function() 
                    return self.internalParser:parse("local _ = " .. mathStr) 
                end)

                if success and tempAst then
                    local expression = extractExpression(tempAst)
                    if expression then
                        -- Tagging is crucial to prevent the obfuscator from eating itself
                        expression.NoObfuscation = true
                        expression.IsGenerated = true
                        return expression
                    end
                end
            end
        end
    end)
end

return NumbersToExpressions
