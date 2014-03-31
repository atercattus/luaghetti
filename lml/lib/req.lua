local M = {}

--- Получение значения GET параметра (URL query string)
function M:get(name, def)
    return ngx.req.get_uri_args()[name] or def
end

return M
