--- Alternative Lua Cache :)
-- Некий аналог php'шного расширения APC

local M = {}

-- nginx.conf http { lua_shared_dict lml_shared 10m; }
local cache = ngx.shared.lml_shared

-- Время жизни кеша байткода в секундах (number)
-- Если указать 0, кеш будет жить до полного перезапуска nginx или вызова M:clear_cache()
local bytecode_cache_ttl = 10

function M:set_bytecode_ttl(ttl)
    bytecode_cache_ttl = ttl
end

function M:get_bytecode_ttl()
    return bytecode_cache_ttl
end

-- @param ttl  number Время жизни в секундах (опционально, по умолчанию сохраняем навечно)
-- @param safe boolean Можно ли удалять из кеша другие значения с не истекшим ttl при нехватке памяти (опционально, по умолчанию не удаляем)
function M:add(key, val, ttl, safe)
    ttl = ttl or 0
    if safe then
        return cache:safe_add(key, val, ttl)
    else
        return cache:add(key, val, ttl)
    end
end

--- Отмечает все элементы кеша как истекшие по ttl
-- Реального освобождения памяти сразу же не происходит
function M:clear_cache()
    return cache:flush_all()
end

-- @param key_lock_ttl number Максимальное время на попытку захвата блокировки в секундах (опционально)
function M:cas(key, old, new, key_lock_ttl)
    local key_lock = key..':lock'
    local key_lock_ttl = key_lock_ttl or 0.5

    local val

    local try_until = ngx.now() + key_lock_ttl
    local locked

    while true do
        locked = cache:add(key_lock, 1, key_lock_ttl)
        val = cache:get(key)
        if locked or (try_until < ngx.now()) then
            break
        end
        ngx.sleep(0.001)
    end

    if not locked then
        --return val == new -- возможен и такой вариант
        return false
    end

    if val ~= old then
        cache:delete(key_lock)
        return false
    end

    local succ = true
    if val ~= new then
        succ = cache:replace(key, new)
    end

    cache:delete(key_lock)
    return succ
end

--- Получение lua функции по исходному коду
-- При наличии кешированного байткода использует его, пропуская стадию компиляции
-- @param str      string|function Строка с Lua кодом или функция, которая возвращает строку с кодом
-- @param filename string Имя chunk'а для str на случай возникновения ошибок
-- @return function или nil при ошибках
-- Бросает исключения
function M:compile_string(str, filename)
    local cache_key = 'tmpl_bytecode:' .. filename
    local bytecode, created_at = cache:get(cache_key)
    local durty_cache = false

    -- кеш байткода устаревает по времени
    if (bytecode_cache_ttl > 0) and bytecode and created_at and (ngx.now() - created_at > bytecode_cache_ttl) then
        bytecode = nil
        created_at = nil
        durty_cache = true
    end

    local lua_func = nil

    if not bytecode then
        local key_lock = cache_key..':lock'
        local key_lock_ttl = 0.5

        local try_until = ngx.now() + key_lock_ttl
        local locked

        while true do
            locked = cache:add(key_lock, 1, key_lock_ttl)
            bytecode, created_at = cache:get(cache_key)
            if locked or (try_until < ngx.now()) then
                break
            end
            ngx.sleep(0.001)
        end

        if (not locked) and (not bytecode) then
            -- лок кем-то занят и байткода нет.
            -- нужно либо выдать ошибку, либо распарсить шаблон (возможен лавинообразный рост нагрузки).
            -- выбираем второй вариант :)
        end

        if durty_cache or (not bytecode) then
            if type(str) == 'function' then
                str = str(filename)
            end
            if str then
                lua_func = assert(loadstring(str, filename))
                bytecode = assert(string.dump(lua_func))
            end
        end

        if locked then
            if lua_func and bytecode then
                cache:set(cache_key, bytecode, 0, ngx.now())
            end
            cache:delete(key_lock)
        end
    end

    if (not lua_func) and bytecode then
        lua_func = loadstring(bytecode, filename)
    end

    return lua_func
end

--- Получение lua функции по исходному коду из файла
-- В файле содержится только lua код. lml-шаблоны в alc не поддерживаются.
-- @param filename string Полный путь до файла
-- Бросает исключения
function M:compile_file(filename)
    return M:compile_string(
        function()
            local str = assert(file:read_all(filename))
            return assert(loadstring(str, filename))
        end,
        filename
    )
end

function M:dec(key, step)
    return cache:incr(key, -(step or 1))
end

function M:delete(key)
    return cache:delete(key)
end

function M:exists(keys)
    if type(keys) ~= 'table' then
        return cache:get(keys) ~= nil
    end

    local res = {}
    for _,key in ipairs(keys) do
        if cache:get(key) ~= nil then
            table.insert(res, key)
        end
    end
    return res
end

local function fetch_one(key, stale)
    if stale then
        return cache:get_stale(key)
    else
        return cache:get(key)
    end
end

--- Получение значения для одного или списка ключей
-- @param keys  string|number|table Для скаляра возвращает единственное значение, для таблицы возвращает таблицу
-- @param stale boolean Можно ли возвращать значения с истекшим ttl (опционально, по умолчанию нельзя)
-- @param def   mixed Значение по умолчанию, если ключ не будет найден (только для таблицы keys из-за особенностей lua)
function M:fetch(keys, stale, def)
    if def == nil then
        def = false
    end

    if type(keys) ~= 'table' then
        return fetch_one(keys, stale)
    end

    local res = {}
    for _,key in ipairs(keys) do
        local val = fetch_one(key, stale)
        if val == nil then
            val = def
        end
        table.insert(res, val)
    end
    return res
end

-- @param ttl number Время жизни в секундах (опционально, по умолчанию сохраняем навечно)
function M:inc(key, step, ttl)
    step = step or 1
    local newval, err = cache:incr(key, step)
    if (not newval) and (err == 'not found') then
        ttl = ttl or 0
        newval, err = cache:add(key, step, ttl)
        if newval then
            newval = step
        end
    end

    return newval
end

-- @param ttl number Время жизни в секундах (опционально, по умолчанию сохраняем навечно)
function M:replace(key, val, ttl)
    return cache:replace(key, val, ttl or 0)
end

-- @param ttl  number Время жизни в секундах (опционально, по умолчанию сохраняем навечно)
-- @param safe boolean Можно ли удалять из кеша другие значения с не истекшим ttl при нехватке памяти (опционально, по умолчанию не удаляем)
function M:store(key, val, ttl, safe)
    ttl = ttl or 0
    if safe then
        return cache:safe_set(key, val, ttl)
    else
        return cache:set(key, val, ttl)
    end
end

return M
