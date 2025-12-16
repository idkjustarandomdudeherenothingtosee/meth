-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua
--
-- This Script provides an Obfuscation Step, that converts Number Literals to expressions
unpack = unpack or table.unpack;

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")

local AstKind = Ast.AstKind;

local NumbersToExpressions = Step:extend();
NumbersToExpressions.Description = "This Step Converts number Literals to Expressions";
NumbersToExpressions.Name = "Numbers To Expressions";

NumbersToExpressions.SettingsDescriptor = {
	Treshold = {
        type = "number",
        default = 1,
        min = 0,
        max = 1,
    },
    InternalTreshold = {
        type = "number",
        default = 0.2,
        min = 0,
        max = 0.8,
    }
}

function NumbersToExpressions:init(settings)
    self.ExpressionGenerators = {
    function(val, depth) -- Addition
        local val2 = math.random(-2^20, 2^20);
        local diff = val - val2;
        -- Use a small tolerance for floating point numbers
        if math.abs((val2 + diff) - val) > 1e-9 then return false; end
        return Ast.AddExpression(self:CreateNumberExpression(val2, depth), self:CreateNumberExpression(diff, depth), false);
    end, 

    function(val, depth) -- Subtraction
        local val2 = math.random(-2^20, 2^20);
        local diff = val + val2;
        if math.abs((diff - val2) - val) > 1e-9 then return false; end
        return Ast.SubExpression(self:CreateNumberExpression(diff, depth), self:CreateNumberExpression(val2, depth), false);
    end,
    
    function(val, depth) -- Multiplication
        -- Avoid division by zero, and use numbers that result in an integer divisor for 'val'
        local val2_options = {};
        for i = 1, 10 do -- Search for small, non-zero divisors
            if val % i == 0 and i ~= 0 then table.insert(val2_options, i); end
            if val % (-i) == 0 and -i ~= 0 then table.insert(val2_options, -i); end
        end
        
        if #val2_options == 0 then return false; end
        
        local val2 = val2_options[math.random(1, #val2_options)];
        local factor = val / val2;
        
        if math.abs((val2 * factor) - val) > 1e-9 then return false; end
        return Ast.MulExpression(self:CreateNumberExpression(val2, depth), self:CreateNumberExpression(factor, depth), false);
    end,
    
    function(val, depth) -- Division
        -- Generate a random divisor and calculate the dividend
        local val2 = math.random(1, 10); -- A small, non-zero divisor
        local dividend = val * val2;
        
        if math.abs((dividend / val2) - val) > 1e-9 then return false; end
        return Ast.DivExpression(self:CreateNumberExpression(dividend, depth), self:CreateNumberExpression(val2, depth), false);
    end,
    
    function(val, depth) -- Aggregation-like function (Sum of Randoms + Difference)
        local num_terms = math.random(3, 5);
        local sum_rand = 0;
        local rand_terms = {};
        for i = 1, num_terms do
            local term = math.random(-100, 100);
            table.insert(rand_terms, term);
            sum_rand = sum_rand + term;
        end

        local required_term = val - sum_rand;
        
        -- Create a chained AddExpression for the random terms
        local expr = self:CreateNumberExpression(rand_terms[1], depth);
        for i = 2, num_terms do
            expr = Ast.AddExpression(expr, self:CreateNumberExpression(rand_terms[i], depth), false);
        end
        
        -- Add the final required term to make the sum equal to 'val'
        return Ast.AddExpression(expr, self:CreateNumberExpression(required_term, depth), false);
    end
}
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    if depth > 0 and math.random() >= self.InternalTreshold or depth > 15 then
        return Ast.NumberExpression(val)
    end

    local generators = util.shuffle({unpack(self.ExpressionGenerators)});
    for i, generator in ipairs(generators) do
        local node = generator(val, depth + 1);
        if node then
            return node;
        end
    end

    return Ast.NumberExpression(val)
end

function NumbersToExpressions:apply(ast)
	visitast(ast, nil, function(node, data)
        if node.kind == AstKind.NumberExpression then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0);
            end
        end
    end)
end

return NumbersToExpressions;
