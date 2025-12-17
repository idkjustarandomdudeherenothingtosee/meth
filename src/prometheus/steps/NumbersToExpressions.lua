-- NumbersToExpressions.lua - Parser-Based (No AST Name Guessing)
local Step = require("prometheus.step")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Parser = require("prometheus.parser")
local Ast = require("prometheus.ast")

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Obfuscates numbers by parsing math strings into AST nodes."
NumbersToExpressions.Name = "Numbers To Expressions (Parser-Based)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1 },
    MaxDepth = { type = "number", default = 3 }
}

function NumbersToExpressions:init(settings)
    -- Initialize a standard parser to convert our strings to AST blocks
    self.internalParser = Parser:new({ LuaVersion = "Lua51" })
end

-- This generates a string of math rather than fighting with AST objects
function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth or math.random() > 0.6 then
        return tostring(val)
    end

    local op = math.random(1, 5)
    if op == 1 then -- Addition
        local r = math.random(-100, 100)
        return string.format("(%s + %s)", self:GenerateMathString(r, depth + 1), self:GenerateMathString(val - r, depth + 1))
    elseif op == 2 then -- Subtraction
        local r = math.random(-100, 100)
        return string.format("(%s - %s)", self:GenerateMathString(val + r, depth + 1), self:GenerateMathString(r, depth + 1))
    elseif op == 3 and val ~= 0 and val % 2 == 0 then -- Multiplication
        return string.format("(%s * 2)", self:GenerateMathString(val / 2, depth + 1))
    elseif op == 4 then -- Division
        local r = math.random(2, 4)
        return string.format("(%s / %s)", self:GenerateMathString(val * r, depth + 1), r)
    else -- Logic "Ternary"
        local junk = math.random(1, 1000)
        return string.format("((1 == 1) and %s or %s)", self:GenerateMathString(val, depth + 1), junk)
    end
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        -- Skip numbers already marked or generated
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                -- 1. Generate the complex math string
                local mathStr = self:GenerateMathString(node.value, 0)
                
                -- 2. Parse it into a temporary AST
                local success, tempAst = pcall(function() 
                    return self.internalParser:parse("return " .. mathStr) 
                end)

                -- 3. Extract the expression from the "return" statement
                if success and tempAst and tempAst.body.statements[1] then
                    local expression = tempAst.body.statements[1].expressions[1]
                    expression.NoObfuscation = true -- Prevent re-processing
                    return expression
                end
            end
        end
    end)
end

return NumbersToExpressions
