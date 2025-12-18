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
    -- Escape backslashes first
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

-- Generate a simple, safe modulo expression
function NumbersToExpressions:GetModuloExpression(val)
    -- Simple modulo expressions that are easy to parse
    local moduloTypes = {
        function(v) return string.format("(%s + (5 %% 4) - 1)", v) end,  -- 5%4 = 1, so adds 0
        function(v) return string.format("(%s + (10 %% 9) - 1)", v) end, -- 10%9 = 1, so adds 0
        function(v) return string.format("(%s + (7 %% 3) - 1)", v) end,  -- 7%3 = 1, so adds 0
        function(v) return string.format("(%s - (100 %% 99) + 1)", v) end -- 100%99 = 1, so adds 0
    }
    local chosen = moduloTypes[math.random(#moduloTypes)]
    return chosen(val)
end

-- Test if expression parses correctly
function NumbersToExpressions:testExpression(expr)
    -- First clean up any potential issues
    expr = expr:gsub("%%+", "%%") -- Ensure only single %
    expr = expr:gsub("(%s*)%%(%s*)", "%1%%%2") -- Ensure spaces around %
    
    local parseString = "local _ = " .. expr
    local success, tempAst = pcall(function() 
        return self.internalParser:parse(parseString) 
    end)
    
    return success and tempAst ~= nil
end

-- Simple expression generation without recursion for base cases
function NumbersToExpressions:GenerateSimpleExpression(val)
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
            if v ~= 0 then
                local factor = math.random(11, 50) / 10
                local base = v / factor
                return string.format("(%.2f * %.1f)", base, factor)
            else
                return "0"
            end
        end,
        function(v)
            if v ~= 0 then
                local factor = math.random(11, 50) / 10
                local base = v * factor
                return string.format("(%.2f / %.1f)", base, factor)
            else
                return "0"
            end
        end
    }
    
    return methods[math.random(#methods)](val)
end

function NumbersToExpressions:GenerateMathString(val, depth)
    if depth >= self.MaxDepth then
        -- Base case - use simple expressions
        return self:GenerateSimpleExpression(val)
    end

    local noise = ""
    if math.random() > 0.7 then
        noise = " + " .. self:GetNoise()
    end

    local result = nil
    local attempts = 0
    
    while attempts < 5 do
        attempts = attempts + 1
        local op = math.random(1, 6)
        
        if op == 1 then -- Addition
            local r = (math.random(-5000, 5000) / 100)
            local expr1 = self:GenerateMathString(r, depth + 1)
            local expr2 = self:GenerateMathString(val - r, depth + 1)
            result = string.format("(%s + %s)%s", expr1, expr2, noise)
        
        elseif op == 2 then -- Subtraction
            local r = (math.random(-5000, 5000) / 100)
            local expr1 = self:GenerateMathString(val + r, depth + 1)
            local expr2 = self:GenerateMathString(r, depth + 1)
            result = string.format("(%s - %s)%s", expr1, expr2, noise)
        
        elseif op == 3 then -- Multiplication
            local factor = (math.random(110, 500) / 100)
            local expr1 = self:GenerateMathString(val / factor, depth + 1)
            result = string.format("(%s * %.2f)%s", expr1, factor, noise)
        
        elseif op == 4 then -- Division
            local factor = (math.random(200, 1000) / 100)
            local expr1 = self:GenerateMathString(val * factor, depth + 1)
            result = string.format("(%s / %.2f)%s", expr1, factor, noise)
        
        elseif op == 5 then -- Ternary logic
            local cond1 = math.random(1, 5)
            local cond2 = cond1 -- Make them equal so expression is always true
            local trueVal = self:GenerateMathString(val, depth + 1)
            local falseVal = "0" -- Simple false value
            result = string.format("((%d == %d) and %s or %s)%s", cond1, cond2, trueVal, falseVal, noise)
        
        else -- Modulo expression (safe version)
            local baseExpr = self:GenerateMathString(val, depth + 1)
            result = self:GetModuloExpression(baseExpr) .. noise
        end
        
        -- Clean up the expression
        result = result:gsub("%s+", " ") -- Normalize spaces
        result = result:gsub("%%+", "%%") -- Ensure single %
        
        -- Test if the expression parses correctly
        if self:testExpression(result) then
            break
        else
            result = nil
        end
    end
    
    -- Fallback if all attempts failed
    if not result then
        return self:GenerateSimpleExpression(val)
    end
    
    return result
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == Ast.AstKind.NumberExpression and not node.NoObfuscation and not node.IsGenerated then
            if math.random() <= self.Treshold then
                
                local mathStr = self:GenerateMathString(node.value, 0)
                
                -- Clean up modulo operators
                mathStr = mathStr:gsub("%%+", "%%")
                
                -- Ensure the expression is valid
                if not self:testExpression(mathStr) then
                    -- Try a simpler approach
                    mathStr = self:GenerateSimpleExpression(node.value)
                end
                
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
