-- NumbersToExpressions.lua - Structure-Agnostic Parser
local Step = require("prometheus.step")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Parser = require("prometheus.parser")
local Ast = require("prometheus.ast")

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Unbreakable number obfuscation using recursive search."
NumbersToExpressions.Name = "Numbers To Expressions (Final)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1 },
    MaxDepth = { type = "number", default = 3 }
}

function NumbersToExpressions:init(settings)
    self.internalParser = Parser:new({ LuaVersion = "Lua51" })
end

-- Helper to find the first expression node inside a parsed block
local function findExpression(node)
    if not node or type(node) ~= "table" then return nil end
    if node.kind and tostring(node.kind):find("Expression") then 
        return node 
    end
    for _, child in pairs(node) do
        local found = findExpression(child)
        if found then return found end
    end
    return nil
end

function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth or math.random() > 0.7 then
        return tostring(val)
    end

    local op = math.random(1, 5)
    if op == 1 then
        local r = math.random(-100, 100)
        return string.format("(%s + %s)", self:GenerateMathString(r, depth + 1), self:GenerateMathString(val - r, depth + 1))
    elseif op == 2 then
        local r = math.random(-100, 100)
        return string.format("(%s - %s)", self:GenerateMathString(val + r, depth + 1), self:GenerateMathString(r, depth + 1))
    elseif op == 3 and val ~= 0 and val % 2 == 0 then
        return string.format("(%s * 2)", self:GenerateMathString(val / 2, depth + 1))
    elseif op == 4 then
        local r = math.random(2, 4)
        return string.format("(%s / %s)", self:GenerateMathString(val * r, depth + 1), r)
    else
        local junk = math.random(1, 1000)
        return string.format("((1 == 1) and %s or %s)", self:GenerateMathString(val, depth + 1), junk)
    end
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        -- Standard check for Number nodes
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:GenerateMathString(node.value, 0)
                local success, tempAst = pcall(function() 
                    return self.internalParser:parse("local _ = " .. mathStr) 
                end)

                if success and tempAst then
                    -- Search the parsed code for the expression we just made
                    local expression = findExpression(tempAst)
                    if expression then
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
