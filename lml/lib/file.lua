local M = {}

-- Чтение всего файла целиком
function M:read_all(path)
    local f = io.open(path, 'r')
    if not f then
        return nil
    end

    local cont = f:read('*all')
    f:close()
    return cont
end

local function _get_mtime(path)
    -- Крайне не эффективная реализация
    local h = assert(io.popen('stat -c %Y '..path..' 2>&1', 'r'))
    local out = assert(h:read('*all'))
    return tonumber(out) or 0
end

--- Получение mtime файла
-- Использовать не рекомендуется :)
-- Бросает исключения
function M:get_mtime(path)
    local succ, res = pcall(_get_mtime, path)
    if succ then
        return res
    else
        return nil
    end
end

return M
