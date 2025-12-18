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
        string.format("((%s * 0))", r),
        string.format("((%s - %s))", r, r),
        string.format("((%s * %s) * 0)", r, math.random())
    }
    return noiseTypes[math.random(#noiseTypes)]
end

function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth then
        -- Randomly choose between decimal or integer representation
        if math.random() > 0.5 then
            return string.format("%.2f", val)
        else
            return tostring(val)
        end
    end

    local op = math.random(1, 6)
    local noise = (math.random() > 0.7) and (" + " .. self:GetNoise()) or ""

    if op == 1 then -- Chaotic Addition
        local r = (math.random(-5000, 5000) / 100)
        return string.format("((%s + %s)%s)", 
            self:GenerateMathString(r, depth + 1), 
            self:GenerateMathString(val - r, depth + 1), 
            noise)
    
    elseif op == 2 then -- Chaotic Subtraction
        local r = (math.random(-5000, 5000) / 100)
        return string.format("((%s - %s)%s)", 
            self:GenerateMathString(val + r, depth + 1), 
            self:GenerateMathString(r, depth + 1), 
            noise)
    
    elseif op == 3 then -- Decimal Multiplication
        local factor = (math.random(110, 500) / 100) -- e.g. 1.1 to 5.0
        return string.format("((%s * %s)%s)", 
            self:GenerateMathString(val / factor, depth + 1), 
            factor, 
            noise)
    
    elseif op == 4 then -- Floating Division
        local factor = (math.random(200, 1000) / 100)
        return string.format("((%s / %s)%s)", 
            self:GenerateMathString(val * factor, depth + 1), 
            factor, 
            noise)
    
    elseif op == 5 then -- Logical Obfuscation
        local junk = math.random() * 1000
        return string.format("(((%s == %s) and %s or %s)%s)", 
            math.random(1,5), 
            math.random(1,5), 
            self:GenerateMathString(val, depth + 1), 
            junk, 
            noise)
    
    else -- Modulo/Multi-Op Garbage
        -- Represents: ((val - 1) + (10 % 9)) -> essentially val
        -- NOTE: %% becomes % in the final string
        return string.format("((%s - 1) + (10 %% 9))", 
            self:GenerateMathString(val, depth + 1))
    end
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:GenerateMathString(node.value, 0)
                
                -- DEBUG: Print the generated math string
                print("Generated math string: " .. mathStr)
                
                -- Escape the string before parsing
                local escapedMathStr = escapeLuaString(mathStr)
                local parseString = "local _ = " .. escapedMathStr
                
                print("Parse string: " .. parseString)
                
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
                        print("WARNING: Could not extract expression from: " .. mathStr)
                    end
                else
                    print("ERROR: Failed to parse math string: " .. mathStr)
                    print("Parse string was: " .. parseString)
                end
            end
        end
    end)
    
    return ast
end

return NumbersToExpressions
