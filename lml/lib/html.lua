local M = {}

local _ = require('vendor.underscore.underscore')

function M:escape(str)
    local trans = {
        ['&'] = '&amp;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
    }
    local trans_chars = table.concat(_.keys(trans), "")
    local r = string.gsub(tostring(str), "["..trans_chars.."]", function(char)
        return trans[char] or char
    end)
    return r
end

return M
