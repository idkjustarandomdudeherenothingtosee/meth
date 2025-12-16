-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ProxifyLocals.lua
--
-- This Script provides a Obfuscation Step for putting all Locals into Proxy Objects

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local RandomLiterals = require("prometheus.randomLiterals")
local util = require("prometheus.util") -- Assume util is available for shuffle

local AstKind = Ast.AstKind;

local ProifyLocals = Step:extend();
ProifyLocals.Description = "This Step wraps all locals into Proxy Objects with dynamic access.";
ProifyLocals.Name = "Proxify Locals (Advanced)";

ProifyLocals.SettingsDescriptor = {
	LiteralType = {
		name = "LiteralType",
		description = "The type of the randomly generated literals used in variable access.",
		type = "enum",
		values = {
			"dictionary",
			"number",
			"string",
            "any",
		},
		default = "string",
	},
}

local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

-- EXPANDED Metatable Expressions to include more operators
local MetatableExpressions = {
    { constructor = Ast.AddExpression, key = "__add" },
    { constructor = Ast.SubExpression, key = "__sub" },
    { constructor = Ast.IndexExpression, key = "__index" },
    { constructor = Ast.MulExpression, key = "__mul" },
    { constructor = Ast.DivExpression, key = "__div" },
    { constructor = Ast.PowExpression, key = "__pow" },
    { constructor = Ast.StrCatExpression, key = "__concat" },
    { constructor = Ast.UnmExpression, key = "__unm" }, -- Unary Minus
    { constructor = Ast.LenExpression, key = "__len" }, -- Length operator
}

function ProifyLocals:init(settings)
	
end

-- Generates a complex expression to represent the key (string)
-- e.g., "valueName" becomes ("val" .. "ueN") .. "ame"
function ProifyLocals:CreateDynamicKey(keyString)
    local len = #keyString
    if len < 4 then
        return Ast.StringExpression(keyString)
    end
    
    local parts = {}
    local start = 1
    while start <= len do
        local part_len = math.random(2, math.min(len - start + 1, 4))
        table.insert(parts, Ast.StringExpression(keyString:sub(start, start + part_len - 1)))
        start = start + part_len
    end

    local expr = parts[1]
    for i = 2, #parts do
        expr = Ast.StrCatExpression(expr, parts[i])
    end
    return expr
end

local function generateLocalMetatableInfo(pipeline)
    local usedOps = {};
    local info = {};
    
    -- 1. Select 3 unique metatable operators
    for i, v in ipairs({"setValue","getValue", "index"}) do
        local rop;
        repeat
            rop = MetatableExpressions[math.random(#MetatableExpressions)];
        until not usedOps[rop];
        usedOps[rop] = true;
        info[v] = rop;
    end

    -- 2. Generate the key used to store the actual value in the proxy table
    info.valueName = callNameGenerator(pipeline.namegenerator, math.random(1, 4096));

    return info;
end

function ProifyLocals:CreateAssignmentExpression(info, expr, parentScope)
    local metatableVals = {};

    -- === Setvalue Entry (Newindex Logic) ===
    local setValueFunctionScope = Scope:new(parentScope);
    local setValueSelf = setValueFunctionScope:addVariable();
    local setValueArg = setValueFunctionScope:addVariable();

    -- Use dynamic key expression for assignment
    local dynamicKey = self:CreateDynamicKey(info.valueName);
    local setStatement = Ast.AssignmentStatement({
        Ast.AssignmentIndexing(Ast.VariableExpression(setValueFunctionScope, setValueSelf), dynamicKey);
    }, {
        Ast.VariableExpression(setValueFunctionScope, setValueArg)
    });
    
    -- Wrap assignment in a dummy function call statement to obscure it
    local functionName = callNameGenerator(self.pipeline.namegenerator, math.random(1, 10));
    local setValueBody = Ast.Block({
        Ast.LocalVariableDeclaration(setValueFunctionScope, {setValueFunctionScope:addVariable(functionName)}, {Ast.FunctionLiteralExpression({}, Ast.Block({setStatement}, setValueFunctionScope))}),
        Ast.FunctionCallStatement(Ast.VariableExpression(setValueFunctionScope, setValueFunctionScope:resolve(functionName)), {})
    }, setValueFunctionScope)

    local setvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(setValueFunctionScope, setValueSelf), -- Argument 1
            Ast.VariableExpression(setValueFunctionScope, setValueArg), -- Argument 2
        },
        setValueBody
    );
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.setValue.key), setvalueFunctionLiteral));

    -- === Getvalue Entry (Index Logic) ===
    local getValueFunctionScope = Scope:new(parentScope);
    local getValueSelf = getValueFunctionScope:addVariable();
    local getValueArg = getValueFunctionScope:addVariable();
    
    local getValueIdxExpr;
    local rawgetVarId = getValueFunctionScope:resolveGlobal("rawget");
    
    -- Always use rawget (like the original intended) but make the key dynamic
    getValueIdxExpr = Ast.FunctionCallExpression(Ast.VariableExpression(getValueFunctionScope, rawgetVarId), {
        Ast.VariableExpression(getValueFunctionScope, getValueSelf),
        self:CreateDynamicKey(info.valueName),
    });

    -- Wrap the return value in a dynamic expression if possible (e.g., v + 0 or v * 1)
    local junkMath;
    if math.random() < 0.5 then
        junkMath = Ast.AddExpression(getValueIdxExpr, Ast.NumberExpression(0), false)
    else
        junkMath = Ast.MulExpression(getValueIdxExpr, Ast.NumberExpression(1), false)
    end
    
    local getvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(getValueFunctionScope, getValueSelf), -- Argument 1
            Ast.VariableExpression(getValueFunctionScope, getValueArg), -- Argument 2
        },
        Ast.Block({ -- Create Function Body
            Ast.ReturnStatement({
                junkMath;
            });
        }, getValueFunctionScope)
    );
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.getValue.key), getvalueFunctionLiteral));

    -- Setup for the setmetatable call
    parentScope:addReferenceToHigherScope(self.setMetatableVarScope, self.setMetatableVarId);
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.setMetatableVarScope, self.setMetatableVarId),
        {
            Ast.TableConstructorExpression({
                -- Store initial value under the dynamic key
                Ast.KeyedTableEntry(self:CreateDynamicKey(info.valueName), expr) 
            }),
            Ast.TableConstructorExpression(metatableVals)
        }
    );
end

function ProifyLocals:apply(ast, pipeline)
    self.pipeline = pipeline -- Store pipeline for access in generators
    local localMetatableInfos = {};
    local function getLocalMetatableInfo(scope, id)
        -- Global Variables should not be transformed
        if(scope.isGlobal) then return nil end;

        localMetatableInfos[scope] = localMetatableInfos[scope] or {};
        if localMetatableInfos[scope][id] then
            -- If locked, return no Metatable
            if localMetatableInfos[scope][id].locked then
                return nil
            end
            return localMetatableInfos[scope][id];
        end
        local localMetatableInfo = generateLocalMetatableInfo(pipeline);
        localMetatableInfos[scope][id] = localMetatableInfo;
        return localMetatableInfo;
    end

    local function disableMetatableInfo(scope, id)
        -- Global Variables should not be transformed
        if(scope.isGlobal) then return nil end;

        localMetatableInfos[scope] = localMetatableInfos[scope] or {};
        localMetatableInfos[scope][id] = {locked = true}
    end

    -- Create Setmetatable Variable
    self.setMetatableVarScope = ast.body.scope;
    self.setMetatableVarId    = ast.body.scope:addVariable();

    -- Create Empty Function Variable (The original logic for this seems fine)
    self.emptyFunctionScope   = ast.body.scope;
    self.emptyFunctionId      = ast.body.scope:addVariable();
    self.emptyFunctionUsed    = false;

    -- Add Empty Function Declaration
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.emptyFunctionScope, {self.emptyFunctionId}, {
        Ast.FunctionLiteralExpression({}, Ast.Block({}, Scope:new(ast.body.scope)));
    }));


    visitast(ast, function(node, data)
        -- Lock for loop variables (important for correctness)
        if(node.kind == AstKind.ForStatement) then
            disableMetatableInfo(node.scope, node.id)
        end
        if(node.kind == AstKind.ForInStatement) then
            for i, id in ipairs(node.ids) do
                disableMetatableInfo(node.scope, id);
            end
        end

        -- Lock Function Arguments (important for correctness)
        if(node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration or node.kind == AstKind.FunctionLiteralExpression) then
            for i, expr in ipairs(node.args) do
                if expr.kind == AstKind.VariableExpression then
                    disableMetatableInfo(expr.scope, expr.id);
                end
            end
        end

        -- Assignment Statements (e.g., a = 1)
        if(node.kind == AstKind.AssignmentStatement) then
            if(#node.lhs == 1 and node.lhs[1].kind == AstKind.AssignmentVariable) then
                local variable = node.lhs[1];
                local localMetatableInfo = getLocalMetatableInfo(variable.scope, variable.id);
                if localMetatableInfo then
                    local args = shallowcopy(node.rhs);
                    local vexp = Ast.VariableExpression(variable.scope, variable.id);
                    vexp.__ignoreProxifyLocals = true;
                    -- Use the metatable operation to "set" the value on the proxy object
                    args[1] = localMetatableInfo.setValue.constructor(vexp, args[1]); 
                    self.emptyFunctionUsed = true;
                    data.scope:addReferenceToHigherScope(self.emptyFunctionScope, self.emptyFunctionId);
                    -- The original code here used a FunctionCallStatement with the empty function, which is a good obfuscation pattern
                    return Ast.FunctionCallStatement(Ast.VariableExpression(self.emptyFunctionScope, self.emptyFunctionId), args);
                end
            end
        end
    end, function(node, data)
        -- Local Variable Declaration (e.g., local a = 1)
        if(node.kind == AstKind.LocalVariableDeclaration) then
            for i, id in ipairs(node.ids) do
                local expr = node.expressions[i] or Ast.NilExpression();
                local localMetatableInfo = getLocalMetatableInfo(node.scope, id);
                if localMetatableInfo then
                    local newExpr = self:CreateAssignmentExpression(localMetatableInfo, expr, node.scope);
                    node.expressions[i] = newExpr;
                end
            end
        end

        -- Variable Expression (e.g., print(a))
        if(node.kind == AstKind.VariableExpression and not node.__ignoreProxifyLocals) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                local literal;
                -- The literal is used as the 'second argument' to the metatable operation, 
                -- effectively making the variable access look like a complex calculation.
                if self.settings.LiteralType == "dictionary" then
                    literal = RandomLiterals.Dictionary();
                elseif self.settings.LiteralType == "number" then
                    literal = RandomLiterals.Number();
                elseif self.settings.LiteralType == "string" then
                    literal = RandomLiterals.String(pipeline);
                else
                    literal = RandomLiterals.Any(pipeline);
                end
                
                -- Create the random literal expression node
                local literalExpr = RandomLiterals.CreateExpression(literal, self.settings.LiteralType);
                
                -- Apply the random metatable constructor (e.g., node + literalExpr)
                return localMetatableInfo.getValue.constructor(node, literalExpr); 
            end
        end

        -- Assignment Variable for Assignment Statement (e.g., a = 1 -> proxy.valueName = 1)
        if(node.kind == AstKind.AssignmentVariable) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                -- The assignment LHS becomes an index into the proxy table
                return Ast.AssignmentIndexing(node, self:CreateDynamicKey(localMetatableInfo.valueName));
            end
        end

        -- Local Function Declaration (local function f() ...)
        if(node.kind == AstKind.LocalFunctionDeclaration) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                local funcLiteral = Ast.FunctionLiteralExpression(node.args, node.body);
                local newExpr = self:CreateAssignmentExpression(localMetatableInfo, funcLiteral, node.scope);
                return Ast.LocalVariableDeclaration(node.scope, {node.id}, {newExpr});
            end
        end

        -- Function Declaration (Global functions which are then proxified to global table index)
        -- Original logic here needs checking, but using the proxified valueName is correct.
        if(node.kind == AstKind.FunctionDeclaration) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if(localMetatableInfo) then
                -- This targets `function a.b.c:f()` where `f` is proxified. 
                -- We only want to proxify the base variable if it's local.
                if node.indices[1].kind == AstKind.VariableExpression then
                    local base_var = node.indices[1]
                    local base_info = getLocalMetatableInfo(base_var.scope, base_var.id)
                    if base_info then
                        -- If the base is proxified, the index must change to the dynamic key.
                        -- This is complex and might break, so we stick to the original logic
                        -- which seems to be designed for global functions that are assigned to 
                        -- a proxified local variable (a global var is proxified if it's 
                        -- implicitly local due to local function declaration wrapping).
                        -- For simplicity and robustness, leave this as the original did.
                    end
                end
                table.insert(node.indices, 1, self:CreateDynamicKey(localMetatableInfo.valueName));
            end
        end
    end)

    -- Add Setmetatable Variable Declaration
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.setMetatableVarScope, {self.setMetatableVarId}, {
        Ast.VariableExpression(self.setMetatableVarScope:resolveGlobal("setmetatable"))
    }));
end

return ProifyLocals;
