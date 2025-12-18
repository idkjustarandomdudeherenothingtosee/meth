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
    MaxDepth = { type = "number", default = 4 }
}

function NumbersToExpressions:init(settings)
    self.internalParser = Parser:new({ LuaVersion = "Lua51" })
end

-- Helper to escape Lua string literals
local function escapeLuaString(str)
    -- Escape backslashes first (most important!)
    str = str:gsub("\\", "\\\\")
    -- Escape quotes
    str = str:gsub("\"", "\\\"")
    -- Escape percent signs in string.format context
    str = str:gsub("%%", "%%%%")
    return str
end

-- Safely extracts the expression from the temp AST
local function extractExpression(tempAst)
    if not tempAst or not tempAst.body or not tempAst.body.statements then return nil end
    local stmt = tempAst.body.statements[1]
    if not stmt then return nil end
    return (stmt.init and stmt.init[1]) or (stmt.values and stmt.values[1]) or (stmt.expressions and stmt.expressions[1])
end

-- Generates "Zero-Sum Noise" (Math that equals 0 but looks complex)
function NumbersToExpressions:GetNoise()
    local r = math.random(1, 1000) / 100
    local noiseTypes = {
        string.format("(%s * 0)", r),
        string.format("(%s - %s)", r, r),
        string.format("((%s * %s) * 0)", r, math.random())
    }
    return noiseTypes[math.random(#noiseTypes)]
end

-- Helper to ensure parentheses are balanced
local function ensureParenthesesBalanced(expr)
    local open = 0
    local maxDepth = 0
    local currentDepth = 0
    
    for i = 1, #expr do
        local c = expr:sub(i, i)
        if c == "(" then
            open = open + 1
            currentDepth = currentDepth + 1
            maxDepth = math.max(maxDepth, currentDepth)
        elseif c == ")" then
            open = open - 1
            currentDepth = currentDepth - 1
            if open < 0 then
                -- Too many closing parentheses
                expr = "(" .. expr
                open = 0
                currentDepth = 1
            end
        end
    end
    
    -- Add missing closing parentheses
    while open > 0 do
        expr = expr .. ")"
        open = open - 1
    end
    
    return expr
end

-- Test if expression parses correctly
function NumbersToExpressions:testExpression(expr)
    local parseString = "local _ = " .. expr
    local success, tempAst = pcall(function() 
        return self.internalParser:parse(parseString) 
    end)
    
    return success and tempAst ~= nil
end

function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth then
        -- Base case - return simple representation
        if math.random() > 0.5 and math.floor(val) ~= val then
            return string.format("%.2f", val)
        else
            return tostring(val)
        end
    end

    local noise = ""
    if math.random() > 0.7 then
        noise = " + " .. self:GetNoise()
    end

    -- Generate a valid expression
    local result = nil
    local attempts = 0
    
    while attempts < 10 do  -- Try up to 10 times to generate a valid expression
        attempts = attempts + 1
        local op = math.random(1, 6)
        
        if op == 1 then -- Chaotic Addition
            local r = (math.random(-5000, 5000) / 100)
            local expr1 = self:GenerateMathString(r, depth + 1)
            local expr2 = self:GenerateMathString(val - r, depth + 1)
            result = string.format("(%s + %s)%s", expr1, expr2, noise)
        
        elseif op == 2 then -- Chaotic Subtraction
            local r = (math.random(-5000, 5000) / 100)
            local expr1 = self:GenerateMathString(val + r, depth + 1)
            local expr2 = self:GenerateMathString(r, depth + 1)
            result = string.format("(%s - %s)%s", expr1, expr2, noise)
        
        elseif op == 3 then -- Decimal Multiplication
            local factor = (math.random(110, 500) / 100) -- e.g. 1.1 to 5.0
            local expr1 = self:GenerateMathString(val / factor, depth + 1)
            result = string.format("(%s * %.2f)%s", expr1, factor, noise)
        
        elseif op == 4 then -- Floating Division
            local factor = (math.random(200, 1000) / 100)
            local expr1 = self:GenerateMathString(val * factor, depth + 1)
            result = string.format("(%s / %.2f)%s", expr1, factor, noise)
        
        elseif op == 5 then -- Logical Obfuscation
            local junk = math.random() * 1000
            local cond1 = math.random(1, 5)
            local cond2 = math.random(1, 5)
            local trueVal = self:GenerateMathString(val, depth + 1)
            local falseVal = string.format("%.2f", junk)
            result = string.format("((%d == %d) and %s or %s)%s", cond1, cond2, trueVal, falseVal, noise)
        
        else -- Modulo/Multi-Op Garbage (simplified version)
            local r = math.random(1, 10)
            result = string.format("(%s - %d + (10 %% 9))", self:GenerateMathString(val, depth + 1), r)
        end
        
        -- Ensure parentheses are balanced
        result = ensureParenthesesBalanced(result)
        
        -- Test if the expression parses correctly
        if self:testExpression(result) then
            break
        else
            result = nil  -- Try again
        end
    end
    
    -- Fallback if all attempts failed
    if not result then
        return string.format("%.2f", val)
    end
    
    return result
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:GenerateMathString(node.value, 0)
                
                -- Ensure parentheses are balanced one more time
                mathStr = ensureParenthesesBalanced(mathStr)
                
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
                    else
                        -- Fallback to original number
                        return nil
                    end
                else
                    -- Fallback to original number if parsing fails
                    return nil
                end
            end
        end
    end)
    
    return ast
end

return NumbersToExpressions
