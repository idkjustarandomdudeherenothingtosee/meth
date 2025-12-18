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

-- XOR function for Lua 5.1 (without bit32 library)
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
    -- Simple XOR encryption with a random key
    local key = math.random(1, 255)
    
    local function encrypt(str)
        local bytes = {}
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = bxor(byte, key)
            -- Convert to decimal string representation
            table.insert(bytes, string.format("\\%03d", encrypted))
        end
        return table.concat(bytes), key
    end
    
    local function genCode()
        -- Lua 5.1 compatible XOR function
        local xorFunction = [[
local function __bxor(a, b)
    local r = 0
    local f = 1
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
    return r
end
]]
        
        return xorFunction .. [[

local function __decrypt_str(encrypted, key)
    local result = ""
    -- Parse escaped decimal sequences like \065\066\067
    for code in encrypted:gmatch("\\(%d%d%d)") do
        local encrypted_byte = tonumber(code) or 0
        local decrypted_byte = __bxor(encrypted_byte, key)
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
        -- Insert all statements from the generated code
        for i = #decryptAst.body.statements, 1, -1 do
            table.insert(ast.body.statements, 1, decryptAst.body.statements[i])
        end
    end
    
    -- Create a scope variable for the decryption function
    local scope = ast.body.scope
    local decryptVar = scope:addVariable()
    
    -- Create an assignment for the decryption function
    local funcDecl = Ast.LocalVariableDeclaration(
        scope,
        { decryptVar },
        { Ast.StringExpression("__decrypt_str") }
    )
    
    -- Insert the variable declaration after the functions
    table.insert(ast.body.statements, #decryptAst.body.statements + 1, funcDecl)
    
    -- Replace string literals with decryption calls
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, key = enc.encrypt(node.value)
            
            -- Create: __decrypt_str("encrypted", key)
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
