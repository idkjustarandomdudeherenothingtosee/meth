local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings using simple XOR encryption"
EncryptStrings.Name = "Encrypt Strings (Simple XOR)"

function EncryptStrings:init(settings) end

-- XOR function for Lua 5.1
local function bxor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then
            result = result + bitval
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

function EncryptStrings:CreateEncryptionService()
    local key = math.random(1, 255)
    
    local function encrypt(str)
        local bytes = {}
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = bxor(byte, key)
            table.insert(bytes, string.format("\\%03d", encrypted))
        end
        return table.concat(bytes), key
    end
    
    -- SIMPLE: Just return the decryption logic as a string to embed
    local function getDecryptFunction()
        return [[
function __decrypt_str(encrypted, key)
    local result = ""
    for code in encrypted:gmatch("\\(%d%d%d)") do
        local r = 0
        local f = 1
        local a = tonumber(code) or 0
        local b = key
        while a > 0 or b > 0 do
            local aa = a % 2
            local bb = b % 2
            if aa ~= bb then
                r = r + f
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            f = f * 2
        end
        result = result .. string.char(r)
    end
    return result
end
]]
    end
    
    return { encrypt = encrypt, getDecryptFunction = getDecryptFunction }
end

function EncryptStrings:apply(ast, pipeline)
    local enc = self:CreateEncryptionService()
    local scope = ast.body.scope
    
    -- Add the decryption function at the start
    local funcCode = enc.getDecryptFunction()
    local funcAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(funcCode)
    
    if funcAst and funcAst.body and funcAst.body.statements then
        -- Insert the function declaration
        table.insert(ast.body.statements, 1, funcAst.body.statements[1])
    end
    
    -- Replace string literals
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, key = enc.encrypt(node.value)
            
            -- Simple function call: __decrypt_str("encrypted", key)
            local call = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, "__decrypt_str"),
                { 
                    Ast.StringExpression(encrypted), 
                    Ast.NumberExpression(key) 
                }
            )
            call.IsGenerated = true
            return call
        end
    end)
    
    return ast
end

return EncryptStrings
