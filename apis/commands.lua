_REGISTERED_COMMANDS = {}

-- registers a command to be used in the dev console
-- @param name: string, the name of the command
-- @param callback: function, the function to be called when the command is run
-- @param short_description: string, a short description of the command
-- @param autocomplete: function(current_arg: string), a function that returns a list of possible completions for the current argument
-- @param usage: string, a string describing the usage of the command (longer, more detailed description of the command's usage)
function registerCommand(name, callback, short_description, autocomplete, usage)
    local logger = getLogger("dev_console")
    if name == nil then
        logger:error("registerCommand -- name is required")
    end
    if callback == nil then
        logger:error("registerCommand -- callback is required")
    end
    if type(callback) ~= "function" then
        logger:error("registerCommand -- callback must be a function")
    end
    if name == nil or callback == nil or type(callback) ~= "function" then
        logger:warn("registerCommand -- name and callback are required, ignoring")
        return
    end
    if short_description == nil then
        logger:warn("registerCommand -- no description provided, please provide a description for the `help` command")
        short_description = "No help provided"
    end
    if usage == nil then
        usage = short_description
    end
    if autocomplete == nil then
        autocomplete = function(current_arg) return nil end
    end
    if type(autocomplete) ~= "function" then
        logger:warn("registerCommand -- autocomplete must be a function")
        autocomplete = function(current_arg) return nil end
    end
    if _REGISTERED_COMMANDS[name] then
        logger:error("Command " .. name .. " already exists")
        return
    end
    _REGISTERED_COMMANDS[name] = {
        call = callback,
        desc = short_description,
        autocomplete = autocomplete,
        usage = usage,
    }
end