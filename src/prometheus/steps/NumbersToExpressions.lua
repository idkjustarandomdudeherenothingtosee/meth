-- NumbersToExpressions.lua - FIXED VERSION
local Step = require("prometheus.step")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Parser = require("prometheus.parser")
local Ast = require("prometheus.ast")

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Converts numbers into chaotic, multi-layer decimal math strings."
NumbersToExpressions.Name = "Numbers To Expressions (Chaotic)"

NumbersToExpressions.SettingsDescriptor = {
    Treshold = { type = "number", default = 1 },
    MaxDepth = { type = "number", default = 2 }
}

function NumbersToExpressions:init(settings)
    self.internalParser = Parser:new({ LuaVersion = "Lua51" })
end

-- Helper to escape Lua string literals
local function escapeLuaString(str)
    return str:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("%%", "%%%%")
end

-- Safely extracts the expression from the temp AST
local function extractExpression(tempAst)
    if not tempAst or not tempAst.body or not tempAst.body.statements then return nil end
    local stmt = tempAst.body.statements[1]
    if not stmt then return nil end
    return (stmt.init and stmt.init[1]) or (stmt.values and stmt.values[1]) or (stmt.expressions and stmt.expressions[1])
end

-- Test if expression parses correctly
function NumbersToExpressions:testExpression(expr)
    local parseString = "local _ = " .. expr
    local success, tempAst = pcall(function() 
        return self.internalParser:parse(parseString) 
    end)
    
    return success and tempAst ~= nil
end

-- Generate math expression using safe variable names that won't conflict
function NumbersToExpressions:GenerateMathExpression(val)
    local expressions = {}
    
    -- Level 1: Basic arithmetic
    local a = math.random(100, 999) / 100
    local b = math.random(100, 999) / 100
    local c = math.random(100, 999) / 100
    
    table.insert(expressions, string.format("(%s * (math.sin(0) + 1.0))", val))
    table.insert(expressions, string.format("(%s + (math.cos(math.pi) + 1.0))", val))
    table.insert(expressions, string.format("(%s / (math.tan(0) + 1.0))", val))
    
    -- Level 2: More complex with multiple math calls
    table.insert(expressions, string.format("((%s * math.abs(%.3f)) / math.abs(%.3f))", val, a, a))
    table.insert(expressions, string.format("((%s + math.floor(%.3f)) - math.floor(%.3f))", val, b, b))
    table.insert(expressions, string.format("((%s - math.ceil(%.3f)) + math.ceil(%.3f))", val, c, c))
    
    -- Level 3: Even more complex
    local pi_val = math.pi
    local e_val = math.exp(1)
    
    table.insert(expressions, string.format("((%s * (math.sin(0) * math.cos(0) + 1.0)) / (math.tan(0) + 1.0))", val))
    table.insert(expressions, string.format("((%s + (math.sqrt(%.3f) - math.sqrt(%.3f))) * 1.0)", val, a, a))
    table.insert(expressions, string.format("((%s - (math.log(%.3f) - math.log(%.3f))) / 1.0)", val, b, b))
    
    -- Level 4: Nested math functions
    table.insert(expressions, string.format("math.abs(%s * math.sin(0) + %s)", val, val))
    table.insert(expressions, string.format("math.floor(math.abs(%s * math.cos(0) + %s))", val, val))
    table.insert(expressions, string.format("math.ceil(math.sqrt(math.abs(%s)))", val))
    
    -- Level 5: Complex expressions that equal the original value
    local r1 = math.random(1, 10)
    local r2 = math.random(1, 10)
    
    table.insert(expressions, string.format("((%s * (math.sin(0)^2 + math.cos(0)^2)) / 1.0)", val))
    table.insert(expressions, string.format("((%s + (math.exp(0) - 1.0)) - 0.0)", val))
    table.insert(expressions, string.format("((%s * math.exp(math.log(1.0))) + (math.sin(0) * %d))", val, r1))
    table.insert(expressions, string.format("((%s / math.exp(math.log(1.0))) - (math.cos(math.pi/2) * %d))", val, r2))
    
    -- Select a random expression
    local selected = expressions[math.random(#expressions)]
    
    -- Add extra parentheses for complexity
    if math.random() > 0.5 then
        selected = string.format("((%s))", selected)
    end
    
    return selected
end

-- Simple number to expression with math functions
function NumbersToExpressions:NumberToExpression(val)
    if val == 0 then
        return "0.0"
    end
    
    -- Try multiple times to get a valid expression
    for attempt = 1, 5 do
        local expr = self:GenerateMathExpression(val)
        
        if self:testExpression(expr) then
            return expr
        end
    end
    
    -- Fallback to simple representation
    if math.floor(val) == val then
        return tostring(val)
    else
        return string.format("%.6f", val)
    end
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:NumberToExpression(node.value)
                
                local escapedMathStr = escapeLuaString(mathStr)
                local parseString = "local _ = " .. escapedMathStr
                
                local success, tempAst = pcall(function() 
                    return self.internalParser:parse(parseString) 
                end)

                if success and tempAst then
                    local expression = extractExpression(tempAst)
                    if expression then
                        expression.NoObfuscation = true
                        expression.IsGenerated = true
                        return expression
                    end
                end
                -- If anything fails, keep the original node
                return nil
            end
        end
    end)
    
    return ast
end

return NumbersToExpressions
