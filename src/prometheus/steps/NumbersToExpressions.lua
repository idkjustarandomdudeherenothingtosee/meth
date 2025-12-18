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
    MaxDepth = { type = "number", default = 3 } -- Reduced from 4 to prevent crashes
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

-- Generates "Zero-Sum Noise" (Math that equals 0 but looks complex)
function NumbersToExpressions:GetNoise()
    local r = math.random(1, 10) / 100
    local noiseTypes = {
        string.format("(%s * 0)", r),
        string.format("(%s - %s)", r, r),
        string.format("(math.sin(0) * %s)", r),
        string.format("(0 / math.max(1, %s))", r),
        string.format("(math.pi - math.pi)")
    }
    return noiseTypes[math.random(#noiseTypes)]
end

-- Test if expression parses correctly
function NumbersToExpressions:testExpression(expr)
    local parseString = "local _ = " .. expr
    local success, tempAst = pcall(function() 
        return self.internalParser:parse(parseString) 
    end)
    
    return success and tempAst ~= nil
end

-- Generate a simple expression without recursion
function NumbersToExpressions:GenerateSimpleExpression(val)
    if val == 0 then return "0" end
    
    -- Limit val to reasonable range to prevent weird divisions
    local safeVal = val
    if math.abs(val) > 1000000 then
        safeVal = val / 1000
    elseif math.abs(val) < 0.0001 and val ~= 0 then
        safeVal = val * 1000
    end
    
    local methods = {
        function(v) 
            local a = math.random(1, 1000) / 100
            local b = v - a
            return string.format("(%.2f + %.2f)", a, b)
        end,
        function(v)
            local a = math.random(1, 1000) / 100
            local b = v + a
            return string.format("(%.2f - %.2f)", b, a)
        end,
        function(v)
            if v == 0 then return "0" end
            local factor = math.random(11, 50) / 10
            local base = v / factor
            if math.abs(base) > 1000000 or math.abs(base) < 0.0001 then
                return string.format("%.4f", v)
            end
            return string.format("(%.2f * %.1f)", base, factor)
        end,
        function(v)
            if v == 0 then return "0" end
            local factor = math.random(11, 50) / 10
            local base = v * factor
            if math.abs(base) > 1000000 or math.abs(base) < 0.0001 then
                return string.format("%.4f", v)
            end
            return string.format("(%.2f / %.1f)", base, factor)
        end,
        function(v)
            -- Power of 2 approach
            if v == 0 then return "0" end
            local pow = math.random(1, 3)
            local base = v / (2 ^ pow)
            if math.abs(base) > 1000000 or math.abs(base) < 0.0001 then
                return string.format("%.4f", v)
            end
            return string.format("(%.2f * %.0f)", base, 2 ^ pow)
        end
    }
    
    local result = methods[math.random(#methods)](safeVal)
    
    -- If result is invalid, return the value directly
    if not self:testExpression(result) then
        return string.format("%.4f", val)
    end
    
    return result
end

-- Non-recursive expression generation
function NumbersToExpressions:GenerateMathString(val)
    -- Start with a simple expression
    local result = self:GenerateSimpleExpression(val)
    
    -- Add some layers of complexity (non-recursive)
    local layers = math.random(1, self.MaxDepth)
    
    for i = 1, layers do
        local noise = ""
        if math.random() > 0.5 then
            noise = " + " .. self:GetNoise()
        end
        
        local op = math.random(1, 4)
        
        if op == 1 then -- Add parentheses with addition
            local r = (math.random(-1000, 1000) / 100)
            local newResult = string.format("((%s + %.2f)%s)", result, r, noise)
            if self:testExpression(newResult) then
                result = newResult
            end
            
        elseif op == 2 then -- Add parentheses with subtraction
            local r = (math.random(-1000, 1000) / 100)
            local newResult = string.format("((%s - %.2f)%s)", result, r, noise)
            if self:testExpression(newResult) then
                result = newResult
            end
            
        elseif op == 3 then -- Ternary wrapper
            local cond1 = math.random(1, 5)
            local cond2 = cond1
            local falseVal = math.random(1, 1000) / 100
            local newResult = string.format("((%d == %d) and %s or %.2f)%s", 
                cond1, cond2, result, falseVal, noise)
            if self:testExpression(newResult) then
                result = newResult
            end
            
        elseif op == 4 then -- Multiply by 1 with parentheses
            local factor = 1.0
            local newResult = string.format("((%s * %.1f)%s)", result, factor, noise)
            if self:testExpression(newResult) then
                result = newResult
            end
        end
    end
    
    return result
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = nil
                local success = false
                
                -- Try up to 3 times to generate a valid expression
                for attempt = 1, 3 do
                    mathStr = self:GenerateMathString(node.value)
                    
                    if self:testExpression(mathStr) then
                        success = true
                        break
                    end
                end
                
                -- If still not valid, use simple representation
                if not success then
                    if math.floor(node.value) == node.value then
                        mathStr = tostring(node.value)
                    else
                        mathStr = string.format("%.4f", node.value)
                    end
                end
                
                local escapedMathStr = escapeLuaString(mathStr)
                local parseString = "local _ = " .. escapedMathStr
                
                local parseSuccess, tempAst = pcall(function() 
                    return self.internalParser:parse(parseString) 
                end)

                if parseSuccess and tempAst then
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
