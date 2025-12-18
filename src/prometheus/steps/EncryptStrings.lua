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

function EncryptStrings:CreateEncryptionService()
    -- Simple XOR encryption with a random key
    local key = math.random(1, 255)
    
    local function encrypt(str)
        local bytes = {}
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = bit32.bxor(byte, key)
            -- Convert to hex for easier embedding
            table.insert(bytes, string.format("\\x%02x", encrypted))
        end
        return table.concat(bytes), key
    end
    
    local function genCode()
        return [[
-- Simple XOR decryption function
local function __decrypt_str(encrypted_hex, key)
    local result = ""
    for i = 1, #encrypted_hex, 4 do
        -- Parse hex byte like "\x41"
        local hex = encrypted_hex:sub(i + 2, i + 3)
        local encrypted_byte = tonumber(hex, 16) or 0
        local decrypted_byte = bit32.bxor(encrypted_byte, key)
        result = result .. string.char(decrypted_byte)
    end
    return result
end
]]
    end
    
    return { encrypt = encrypt, genCode = genCode }
end

function EncryptStrings:apply(ast, pipeline)
    local enc = self:CreateEncryptionService()
    
    -- Parse and insert the decryption function at the beginning
    local decryptAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(enc.genCode())
    if decryptAst and decryptAst.body and decryptAst.body.statements then
        -- Insert the function declaration at the start
        table.insert(ast.body.statements, 1, decryptAst.body.statements[1])
    end
    
    -- Create a scope variable for the decryption function
    local scope = ast.body.scope
    local decryptVar = scope:addVariable()
    
    -- Create an assignment for the decryption function
    -- This makes sure the function is properly named in the scope
    local funcDecl = Ast.LocalVariableDeclaration(
        scope,
        { decryptVar },
        { Ast.StringExpression("__decrypt_str") }
    )
    
    -- Insert the variable declaration after the function
    table.insert(ast.body.statements, 2, funcDecl)
    
    -- Replace string literals with decryption calls
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, key = enc.encrypt(node.value)
            
            -- Create: __decrypt_str("encrypted_hex", key)
            local call = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decryptVar),
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
