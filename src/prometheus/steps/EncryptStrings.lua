-- EncryptStrings.lua - Debug version to understand API
local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Debug string transformation"
EncryptStrings.Name = "String Debug"

function EncryptStrings:init(settings) end

function EncryptStrings:apply(ast, pipeline)
    print("=== EncryptStrings Debug ===")
    print("Available Ast fields:")
    for k, v in pairs(Ast) do
        if type(v) == "table" then
            print("  " .. k .. " (table)")
        elseif type(v) == "function" then
            print("  " .. k .. " (function)")
        end
    end
    
    print("\nAstKind values:")
    for k, v in pairs(AstKind) do
        print("  " .. k .. " = " .. tostring(v))
    end
    
    -- Look at a sample string node structure
    local sample_string = nil
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not sample_string then
            sample_string = node
            print("\nSample StringExpression node:")
            for k, v in pairs(node) do
                print("  " .. k .. ": " .. tostring(v))
            end
        end
    end)
    
    -- Try to create a simple AST node
    print("\nTrying to create nodes:")
    
    -- Check what constructor functions exist
    if Ast.NumberExpression then
        print("✓ Ast.NumberExpression exists")
        local num = Ast.NumberExpression(123)
        print("  Created: " .. tostring(num))
    else
        print("✗ Ast.NumberExpression doesn't exist")
    end
    
    if Ast.StringExpression then
        print("✓ Ast.StringExpression exists")
        local str = Ast.StringExpression("test")
        print("  Created: " .. tostring(str))
    else
        print("✗ Ast.StringExpression doesn't exist")
    end
    
    return ast
end

return EncryptStrings
