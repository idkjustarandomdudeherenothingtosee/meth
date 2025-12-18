-- EncryptStrings.lua - Safe Lua 5.4 Version
-- Uses proper Prometheus AST construction

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings using safe Lua 5.4 compatible encoding"
EncryptStrings.Name = "Encrypt Strings (Lua 5.4 Safe)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    -- Use only characters that are safe for Lua strings
    local safe_chars = {}
    for i = 65, 90 do  -- A-Z
        table.insert(safe_chars, string.char(i))
    end
    for i = 97, 122 do -- a-z
        table.insert(safe_chars, string.char(i))
    end
    for i = 48, 57 do  -- 0-9
        table.insert(safe_chars, string.char(i))
    end
    
    -- Create encoding/decoding tables
    local char_to_index = {}
    local index_to_char = {}
    
    for i, char in ipairs(safe_chars) do
        char_to_index[char] = i - 1
        index_to_char[i - 1] = char
    end
    
    local base = #safe_chars
    
    -- Simple encryption: character shift + XOR
    local function encrypt_string(str)
        -- Generate random shift (1-25)
        local shift = math.random(1, 25)
        -- Generate random XOR key
        local xor_key = math.random(0, 255)
        
        local encoded = {}
        
        -- First two chars encode the shift and xor_key
        table.insert(encoded, index_to_char[shift])
        table.insert(encoded, index_to_char[xor_key % base])
        
        -- Encode the string
        for i = 1, #str do
            local byte = string.byte(str, i)
            -- Apply shift and XOR
            local encrypted = (byte + shift) ~ xor_key
            -- Convert to base-N representation (2 chars)
            local high = math.floor(encrypted / base)
            local low = encrypted % base
            table.insert(encoded, index_to_char[high])
            table.insert(encoded, index_to_char[low])
        end
        
        return table.concat(encoded), shift, xor_key
    end
    
    -- Generate simple, safe decryption code as string
    local function genDecryptionCode()
        return [[
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local char_index = {}
    
    for i = 1, #chars do
        char_index[chars:sub(i, i)] = i - 1
    end
    
    local base = #chars
    local str_cache = {}
    local STR = {}
    
    local function DEC(encoded)
        if str_cache[encoded] then
            return str_cache[encoded]
        end
        
        local shift = char_index[encoded:sub(1, 1)]
        local xor_key = char_index[encoded:sub(2, 2)]
        local result = {}
        
        for i = 3, #encoded, 2 do
            local high_char = encoded:sub(i, i)
            local low_char = encoded:sub(i + 1, i + 1)
            local high = char_index[high_char] or 0
            local low = char_index[low_char] or 0
            local val = high * base + low
            local decrypted = (val ~ xor_key) - shift
            result[#result + 1] = string.char(decrypted)
        end
        
        local decrypted_str = table.concat(result)
        str_cache[encoded] = decrypted_str
        return decrypted_str
    end
end
]]
    end
    
    return {
        encrypt = function(str)
            local encoded, shift, xor_key = encrypt_string(str)
            return encoded
        end,
        genCode = genDecryptionCode
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    local scope = ast.body.scope
    
    -- Create variable names
    local decrypt_var = scope:addVariable()
    local strings_var = scope:addVariable()
    
    -- Parse the decryption code
    local decryption_code = Encryptor.genCode()
    
    -- Try to parse the code
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }) -- Use Lua51 for compatibility
    local parse_result = parser:parse(decryption_code)
    
    if parse_result and parse_result.body then
        -- Get the do statement from the parsed code
        local do_statement = parse_result.body.statements[1]
        
        if do_statement and do_statement.kind == AstKind.DoStatement then
            -- Set parent scope
            do_statement.body.scope.parent = scope
            
            -- Rename DEC and STR in the do block
            local function rename_in_do(node)
                if node.kind == AstKind.FunctionDeclaration then
                    -- Check if this is the DEC function
                    local func_name = node.scope:getVariableName(node.id)
                    if func_name == "DEC" then
                        node.id = decrypt_var
                    end
                elseif node.kind == AstKind.LocalVariableDeclaration then
                    -- Check if this is the STR variable
                    for i, var in ipairs(node.ids) do
                        local var_name = node.scope:getVariableName(var)
                        if var_name == "STR" then
                            node.ids[i] = strings_var
                        end
                    end
                elseif node.kind == AstKind.VariableExpression then
                    -- Rename variable references
                    local var_name = node.scope:getVariableName(node.id)
                    if var_name == "DEC" then
                        node.id = decrypt_var
                    elseif var_name == "STR" then
                        node.id = strings_var
                    end
                end
            end
            
            visitast(do_statement, nil, rename_in_do)
            
            -- Insert the do block at the beginning
            table.insert(ast.body.statements, 1, do_statement)
        end
    else
        -- Fallback: create a simple do block manually
        print("Warning: Could not parse decryption code, using fallback")
        
        -- Create a simple do block with basic encryption
        local do_scope = Scope:new(scope)  -- Create child scope
        
        -- Create variable declarations
        local chars_var = do_scope:addVariable()
        local char_index_var = do_scope:addVariable()
        local base_var = do_scope:addVariable()
        local str_cache_var = do_scope:addVariable()
        
        -- Create STR variable
        local str_var = do_scope:addVariable()
        
        -- Create DEC function
        local dec_func_var = do_scope:addVariable()
        local encoded_param = do_scope:addVariable()
        
        -- Build simple statements
        local statements = {}
        
        -- chars = "ABC..."
        table.insert(statements, Ast.LocalVariableDeclaration(
            do_scope,
            {chars_var},
            {Ast.StringExpression("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")}
        ))
        
        -- char_index = {}
        table.insert(statements, Ast.LocalVariableDeclaration(
            do_scope,
            {char_index_var},
            {Ast.TableExpression(do_scope)}
        ))
        
        -- STR = {}
        table.insert(statements, Ast.LocalVariableDeclaration(
            do_scope,
            {str_var},
            {Ast.TableExpression(do_scope)}
        ))
        
        -- str_cache = {}
        table.insert(statements, Ast.LocalVariableDeclaration(
            do_scope,
            {str_cache_var},
            {Ast.TableExpression(do_scope)}
        ))
        
        -- base = #chars
        table.insert(statements, Ast.LocalVariableDeclaration(
            do_scope,
            {base_var},
            {Ast.UnaryOperatorExpression("#", Ast.VariableExpression(do_scope, chars_var))}
        ))
        
        -- Create a simple DEC function
        local dec_func = Ast.FunctionDeclaration(
            do_scope,
            dec_func_var,
            {encoded_param},
            Ast.Block(do_scope)
        )
        
        table.insert(statements, dec_func)
        
        -- Create do block
        local do_block = Ast.DoStatement(do_scope)
        do_block.body.statements = statements
        
        -- Insert at beginning
        table.insert(ast.body.statements, 1, do_block)
    end
    
    -- Declare outer variables
    table.insert(ast.body.statements, 1, 
        Ast.LocalVariableDeclaration(scope, {decrypt_var, strings_var}, {})
    )
    
    -- Replace string literals with encrypted versions
    self:replaceStringLiterals(ast, Encryptor, scope, decrypt_var, strings_var)
    
    return ast
end

function EncryptStrings:replaceStringLiterals(ast, Encryptor, scope, decrypt_var, strings_var)
    -- Track replacements to make
    local replacements = {}
    
    local function findStringLiterals(node, parent, key)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            table.insert(replacements, {
                node = node,
                parent = parent,
                key = key,
                encrypted = Encryptor.encrypt(node.value)
            })
        end
        
        -- Recurse through AST
        if node.body and node.body.statements then
            for i, stmt in ipairs(node.body.statements) do
                findStringLiterals(stmt, node.body, i)
            end
        end
        
        if node.statements then
            for i, stmt in ipairs(node.statements) do
                findStringLiterals(stmt, node, i)
            end
        end
        
        if node.expressions then
            for i, expr in ipairs(node.expressions) do
                findStringLiterals(expr, node, i)
            end
        end
        
        if node.value and node.value.kind then
            findStringLiterals(node.value, node, "value")
        end
        
        if node.key and node.key.kind then
            findStringLiterals(node.key, node, "key")
        end
        
        if node.init then
            for i, init in ipairs(node.init) do
                if init.kind then
                    findStringLiterals(init, node.init, i)
                end
            end
        end
    end
    
    findStringLiterals(ast)
    
    -- Apply replacements
    for _, replacement in ipairs(replacements) do
        local encrypted_str = replacement.encrypted
        
        -- Create: STRINGS[DECRYPT(encrypted_str)]
        local decrypt_call = Ast.FunctionCallExpression(
            Ast.VariableExpression(scope, decrypt_var),
            {Ast.StringExpression(encrypted_str)}
        )
        
        local index_expr = Ast.IndexExpression(
            Ast.VariableExpression(scope, strings_var),
            decrypt_call
        )
        
        index_expr.IsGenerated = true
        
        -- Replace the node
        if replacement.parent then
            if replacement.parent.statements and replacement.key then
                replacement.parent.statements[replacement.key] = index_expr
            elseif replacement.parent.expressions and replacement.key then
                replacement.parent.expressions[replacement.key] = index_expr
            elseif replacement.parent.value == replacement.node then
                replacement.parent.value = index_expr
            elseif replacement.parent.key == replacement.node then
                replacement.parent.key = index_expr
            end
        end
    end
end

return EncryptStrings
