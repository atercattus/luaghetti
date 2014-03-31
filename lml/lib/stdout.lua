--- Управление выводом
-- Универсальный print + частичная реализация функций ob_* из PHP

local M = {}

local ob_buff = nil

function M:print(...)
    if not ob_buff then
        ngx.print(...)
    else
        table.insert(ob_buff, ...)
    end
end

function M:ob_clean()
    if ob_buff then
        ob_buff = {}
    end
end

function M:ob_end_clean()
    ob_buff = nil
end

function M:ob_end_flush()
    if ob_buff then
        local b = ob_buff
        ob_buff = nil
        self:print(b)
    end
end

function M:ob_flush()
    if ob_buff then
        local b = ob_buff
        ob_buff = nil
        self:print(b)
        ob_buff = {}
    end
end

function M:ob_get_clean()
    local b = ob_buff
    if ob_buff then
        ob_buff = {}
    end
    return b
end

function M:ob_get_contents()
    return ob_buff
end

function M:ob_get_flush()
    if not ob_buff then
        return nil
    end

    local b = ob_buff
    ob_buff = nil
    return b
end

function M:ob_start()
    if not ob_buff then
        ob_buff = {}
    end
end

return M
