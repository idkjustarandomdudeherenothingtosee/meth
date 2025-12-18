-- EncryptStrings.lua - Lua 5.4 Compatible Version
-- Uses a different approach to avoid string escape issues

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings using base64-like encoding for Lua 5.4 compatibility"
EncryptStrings.Name = "Encrypt Strings (Safe Base64)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    -- Use a safe character set that won't cause Lua parsing issues
    local safe_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
    
    -- Create lookup tables
    local char_to_value = {}
    local value_to_char = {}
    
    for i = 1, #safe_chars do
        local char = safe_chars:sub(i, i)
        char_to_value[char] = i - 1
        value_to_char[i - 1] = char
    end
    
    -- Simple XOR-based encryption
    local function generate_key(length)
        local key = {}
        for i = 1, length do
            key[i] = math.random(0, 255)
        end
        return key
    end
    
    local function encrypt_string(str)
        -- Generate a random key
        local key = generate_key(#str)
        local encoded_chars = {}
        
        -- XOR encrypt and encode
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = byte ~ key[i]
            
            -- Encode as two safe characters (2 chars per byte = 512 possible values)
            local high = math.floor(encrypted / #safe_chars)
            local low = encrypted % #safe_chars
            
            table.insert(encoded_chars, value_to_char[high])
            table.insert(encoded_chars, value_to_char[low])
        end
        
        local encoded = table.concat(encoded_chars)
        local key_encoded = {}
        
        -- Encode key similarly
        for i = 1, #key do
            local high = math.floor(key[i] / #safe_chars)
            local low = key[i] % #safe_chars
            table.insert(key_encoded, value_to_char[high])
            table.insert(key_encoded, value_to_char[low])
        end
        
        return encoded, table.concat(key_encoded)
    end
    
    local function genDecryptionCode()
        -- This generates safe Lua code without problematic string escapes
        local code = [[
do
    local safe_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
    local char_to_value = {}
    
    for i = 1, #safe_chars do
        char_to_value[safe_chars:sub(i, i)] = i - 1
    end
    
    local string_cache = {}
    local STRING_TABLE = setmetatable({}, {
        __index = function(t, id)
            return string_cache[id]
        end
    })
    
    function DECODE_STRING(encoded, key_encoded)
        local cache_key = encoded .. ":" .. key_encoded
        if string_cache[cache_key] then
            return cache_key
        end
        
        -- Decode key
        local key = {}
        for i = 1, #key_encoded, 2 do
            local high_char = key_encoded:sub(i, i)
            local low_char = key_encoded:sub(i + 1, i + 1)
            local high = char_to_value[high_char] or 0
            local low = char_to_value[low_char] or 0
            key[#key + 1] = high * #safe_chars + low
        end
        
        -- Decode and decrypt string
        local result = {}
        local key_index = 1
        
        for i = 1, #encoded, 2 do
            local high_char = encoded:sub(i, i)
            local low_char = encoded:sub(i + 1, i + 1)
            local high = char_to_value[high_char] or 0
            local low = char_to_value[low_char] or 0
            local encrypted = high * #safe_chars + low
            
            local decrypted = encrypted ~ key[key_index]
            key_index = key_index + 1
            
            result[#result + 1] = string.char(decrypted)
        end
        
        string_cache[cache_key] = table.concat(result)
        return cache_key
    end
end
]]
        return code
    end
    
    return {
        encrypt = encrypt_string,
        genCode = genDecryptionCode
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    
    -- Parse the decryption code
    local decryptionCode = Encryptor.genCode()
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua54 })
    local success, newAst = pcall(function() return parser:parse(decryptionCode) end)
    
    if not success or not newAst or not newAst.body then
        -- Try a simpler approach - just wrap the entire thing in a do block
        decryptionCode = "do\n" .. decryptionCode .. "\nend"
        newAst = parser:parse(decryptionCode)
        
        if not newAst or not newAst.body then
            -- Last resort: create a minimal AST manually
            print("WARNING: Parser failed, using manual AST construction")
            return self:applyManual(ast, Encryptor)
        end
    end
    
    local scope = ast.body.scope
    
    -- Create variables
    local decodeFuncVar = scope:addVariable()
    local stringTableVar = scope:addVariable()
    
    -- Find and rename the DECODE_STRING function and STRING_TABLE
    local function renameVars(node)
        if node.kind == AstKind.FunctionDeclaration then
            if node.name and node.name == "DECODE_STRING" then
                node.name = decodeFuncVar.name
            end
        elseif node.kind == AstKind.AssignmentVariable then
            for i, var in ipairs(node.variables) do
                if var.name == "STRING_TABLE" then
                    node.variables[i] = stringTableVar
                end
            end
        elseif node.kind == AstKind.VariableExpression then
            if node.name == "STRING_TABLE" then
                node.name = stringTableVar.name
            elseif node.name == "DECODE_STRING" then
                node.name = decodeFuncVar.name
            end
        end
    end
    
    -- Traverse and rename
    visitast(newAst, nil, renameVars)
    
    -- Add the decryption code to the beginning
    if newAst.body and newAst.body.statements then
        for i = #newAst.body.statements, 1, -1 do
            table.insert(ast.body.statements, 1, newAst.body.statements[i])
        end
    end
    
    -- Declare local variables
    table.insert(ast.body.statements, 1, 
        Ast.LocalVariableDeclaration(scope, {decodeFuncVar, stringTableVar}, {})
    )
    
    -- Replace string literals
    local replacements = {}
    
    local function replaceString(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encoded, key = Encryptor.encrypt(node.value)
            
            -- Create function call: DECODE_STRING(encoded, key)
            local decodeCall = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decodeFuncVar),
                {
                    Ast.StringExpression(encoded),  -- This should be safe (only alphanumeric)
                    Ast.StringExpression(key)       -- This should be safe too
                }
            )
            
            -- Create index: STRING_TABLE[DECODE_STRING(...)]
            local indexExpr = Ast.IndexExpression(
                Ast.VariableExpression(scope, stringTableVar),
                decodeCall
            )
            
            indexExpr.IsGenerated = true
            return indexExpr
        end
    end
    
    -- We need to actually replace the nodes in the AST
    -- This depends on how Prometheus's AST replacement works
    -- For now, we'll use a simplified approach
    local function traverseAndReplace(node, parent, index)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local replacement = replaceString(node)
            if replacement and parent and index then
                if parent.kind == AstKind.TableEntry then
                    parent.value = replacement
                elseif parent.statements then
                    parent.statements[index] = replacement
                elseif parent.expressions then
                    parent.expressions[index] = replacement
                end
            end
        elseif node.body then
            if node.body.statements then
                for i, stmt in ipairs(node.body.statements) do
                    traverseAndReplace(stmt, node.body, i)
                end
            end
        elseif node.statements then
            for i, stmt in ipairs(node.statements) do
                traverseAndReplace(stmt, node, i)
            end
        elseif node.expressions then
            for i, expr in ipairs(node.expressions) do
                traverseAndReplace(expr, node, i)
            end
        end
    end
    
    traverseAndReplace(ast)
    
    return ast
end

function EncryptStrings:applyManual(ast, Encryptor)
    -- Manual fallback method
    local scope = ast.body.scope
    
    -- Create simple decryption code as AST nodes directly
    local decryptionCode = [[
local safe_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
local char_to_value = {}
for i = 1, #safe_chars do
    char_to_value[safe_chars:sub(i, i)] = i - 1
end

local string_cache = {}
local STR_TBL = setmetatable({}, {
    __index = function(t, id) return string_cache[id] end
})

function DEC_FUNC(enc, key_enc)
    local cache_key = enc .. ":" .. key_enc
    if string_cache[cache_key] then return cache_key end
    
    local key = {}
    for i = 1, #key_enc, 2 do
        local h = char_to_value[key_enc:sub(i, i)] or 0
        local l = char_to_value[key_enc:sub(i+1, i+1)] or 0
        key[#key+1] = h * 62 + l
    end
    
    local result = {}
    for i = 1, #enc, 2 do
        local h = char_to_value[enc:sub(i, i)] or 0
        local l = char_to_value[enc:sub(i+1, i+1)] or 0
        local encrypted = h * 62 + l
        local decrypted = encrypted ~ key[#result+1]
        result[#result+1] = string.char(decrypted)
    end
    
    string_cache[cache_key] = table.concat(result)
    return cache_key
end
]]
    
    -- Parse this simpler code
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua54 })
    local newAst = parser:parse(decryptionCode)
    
    if newAst and newAst.body then
        -- Insert at beginning
        for i = #newAst.body.statements, 1, -1 do
            table.insert(ast.body.statements, 1, newAst.body.statements[i])
        end
    end
    
    -- Replace strings (simplified)
    local function replaceStrings(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encoded, key = Encryptor.encrypt(node.value)
            -- Create a simple call
            local call = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, scope:getVariable("DEC_FUNC")),
                {
                    Ast.StringExpression(encoded),
                    Ast.StringExpression(key)
                }
            )
            
            local index = Ast.IndexExpression(
                Ast.VariableExpression(scope, scope:getVariable("STR_TBL")),
                call
            )
            
            index.IsGenerated = true
            return index
        end
    end
    
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            return replaceStrings(node)
        end
    end)
    
    return ast
end

return EncryptStrings
