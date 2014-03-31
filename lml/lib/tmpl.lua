--- lml шаблонизатор

local M = {}

local file = require 'lib.file'
local stdout = require 'lib.stdout'
local alc = require 'lib.alc'

local root_path = './'
local file_ext = '.lml'

-- Всегда доступные библиотеки. Остальные нужно подгружать через require
-- Имхо, лучше все всегда подгружать явно, без подобной магии.
local required_libs = {'stdout', 'html', 'req', 'tmpl'}

--- Задание корневой директории с шаблонами
function M:set_root(path)
    root_path = path

    if '/' ~= root_path:sub(root_path:len()) then
        root_path = root_path .. '/'
    end
end

--- Задание расширения имен файлов с шаблонами
function M:set_ext(ext)
    file_ext = ext
end

--- Выбор ограничителя для многострочных строк
-- В шаблоне могут встречаться символы, похожие на многострочные ограничители строк [=[ и т.п.
-- @param str       string Текст шаблона
-- @param max_tries number Максимальное число попыток подобрать огнаничители. В случае неудачи вернет (nil, nil)
-- @return (string, string) Кортеж из начального и терминального разделителей
local function search_unused_multiline(str, max_tries)
    local eqCnt = 0

    max_tries = max_tries or 20

    repeat
        local delim = string.rep('=', eqCnt)
        local delim_open = '[' .. delim .. '['
        local delim_close = ']' .. delim .. ']'

        if not str:find(delim_open, 1, true) and not str:find(delim_close, 1, true) then
            return delim_open, delim_close
        end

        eqCnt = eqCnt + 1
    until eqCnt > max_tries

    return nil, nil
end

--- Разбор lml шаблона и перевод его в текст чистого lua кода
-- @param str      string Строка lml шаблона
-- @param filename string Имя chunk'а для str на случай возникновения ошибок
-- @return string Lua код, который получается из шаблона
-- Бросает исключение
local function parse_tmpl(str, filename)
    local tag_open = '<?lml'
    local tag_close = '?>'

    local delim_open, delim_close = search_unused_multiline(str)

    local tmpl_chunks = {}

    local function raw_into_code(raw)
        table.insert(tmpl_chunks, 'stdout:print('..delim_open..raw..delim_close..');')
    end

    local prev_f = 1
    repeat
        local open_f, open_t = str:find(tag_open, prev_f, true)
        if not open_f then
            break
        end

        if open_f > prev_f then
            raw_into_code(str:sub(prev_f, open_f-1))
        end

        local close_f, close_t = str:find(tag_close, open_t+1, true)
        assert(close_f, 'Wrong syntax: there is no closing tag '..tag_close..' for '..tag_open)

        table.insert(tmpl_chunks, str:sub(open_t+1, close_f-1))

        prev_f = close_t+1
    until false

    local tail_f = prev_f
    if tail_f <= str:len() then
        raw_into_code(str:sub(tail_f))
    end

    -- подгрузка встроенных библиотек
    for _,l in ipairs(required_libs) do
        table.insert(tmpl_chunks, 1, 'local '..l..' = require("lib.'..l..'");')
    end

    return table.concat(tmpl_chunks, ' ')
end

local function _include_string(str, filename)
    local lua_func = alc:compile_string(str, filename)
    if lua_func then
        lua_func()
    end
end

--- Загрузка шаблона из строки
-- @return boolean Успешность компиляции и выполнения шаблона
function M:include_string(str, filename)
    local succ, err = pcall(_include_string, str, filename)
    if not succ then
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR

        local errstr = 'Error (' .. filename .. '): ' .. err
        ngx.log(ngx.ERR, errstr)
        ngx.say(errstr)
        return ngx.exit(ngx.HTTP_OK)
    end
    return succ
end

--- Загрузка шаблона по имени (без пути и расширения) файла
-- @return boolean Успешность компиляции и выполнения шаблона
function M:include(name)
    local path = root_path .. name .. file_ext

    M:include_string(
        function(filename)
            local str = assert(file:read_all(filename))
            return assert(parse_tmpl(str, filename))
        end,
        path
    )
end

return M
