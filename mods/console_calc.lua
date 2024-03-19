local utf8 = require("utf8")
local LINE_HEIGHT = 20
local math = require('math')



local console = {
    logger = getLogger("dev_console"),
    log_level = "INFO",
    is_open = false,
    cmd = "> ",
    max_lines = love.graphics.getHeight() / LINE_HEIGHT,
    start_line_offset = 1,
    history_index = 0,
    command_history = {},
    history_path = "dev_console.history",
    modifiers = {
        capslock = false,
        scrolllock = false,
        numlock = false,
        shift = false,
        ctrl = false,
        alt = false,
        meta = false,
    },

    calc_joker = function(self)
        console.logger:info("hello")
    end,
    toggle = function(self)
        self.is_open = not self.is_open
        love.keyboard.setKeyRepeat(self.is_open)  -- set key repeat to true when console is open
        if self.is_open then
            self.start_line_offset = self.max_lines - 1
            local oldTextInput = love.textinput
            love.textinput = function(character)
                self.cmd = self.cmd .. character
            end
        else
            love.textinput = nil
        end
    end,
    longestCommonPrefix = function(self, strings)
        if #strings == 0 then
            return ""
        end
        local prefix = strings[1]
        for i = 2, #strings do
            local str = strings[i]
            local j = 1
            while j <= #prefix and j <= #str and prefix:sub(j, j) == str:sub(j, j) do
                j = j + 1
            end
            prefix = prefix:sub(1, j - 1)
        end
        return prefix
    end,
    tryAutocomplete = function(self)
        local command = self.cmd:sub(3) -- remove the "> " prefix
        local cmd = {}
        -- split command into parts
        for part in command:gmatch("%S+") do
            table.insert(cmd, part)
        end
        if #cmd == 0 then
            -- no command typed, do nothing (no completions possible)
            logger:trace("No command typed")
            return nil
        end
        local completions = {}
        if #cmd == 1 then
            -- only one part, try to autocomplete the command
            -- find all commands that start with the typed string, then complete the characters until the next character is not a match
            for name, _ in pairs(_REGISTERED_COMMANDS) do
                if name:find(cmd[1], 1, true) == 1 then -- name starts with cmd[1]
                    table.insert(completions, name)
                end
            end
        else
            -- more than one part, try to autocomplete the arguments
            local commandName = cmd[1]
            local command = _REGISTERED_COMMANDS[commandName]
            if command then
                completions = command.autocomplete(cmd[#cmd]) or {}
            end
        end
        logger:trace("Autocomplete matches: " .. #completions .. " " .. table.concat(completions, ", "))
        if #completions == 0 then
            -- no completions found
            return nil
        elseif #completions == 1 then
            return completions[1]
        else
            -- complete until the common prefix of all matches
            return self:longestCommonPrefix(completions)
        end
    end,
    getMessageColor = function (self, message)
        if message.level == "PRINT" then
            return 1, 1, 1
        end
        if message.level == "INFO" then
            return 0, 0.9, 1
        end
        if message.level == "WARN" then
            return 1, 0.5, 0
        end
        if message.level == "ERROR" then
            return 1, 0, 0
        end
        if message.level == "DEBUG" then
            return 0.16, 0, 1
        end
        if message.level == "TRACE" then
            return 1, 1, 1
        end
        return 1, 1, 1
    end,
    getFilteredMessages = function(self)
        local filtered = {}
        for _, message in ipairs(ALL_MESSAGES) do
            if message.level_numeric >= self.logger.log_levels[self.log_level] then
                table.insert(filtered, message)
            end
        end
        return filtered
    end,
    getMessagesToDisplay = function(self)
        local text = {}
        local i = 1
        local textLength = 0
        local all_messages = self:getFilteredMessages()
        while textLength < self.max_lines do
            local index = #all_messages - i + self.start_line_offset
            if index < 1 then
                break
            end
            local message = all_messages[index]
            if message then
                table.insert(text, message)
                textLength = textLength + 1
            end
            i = i + 1
        end
        -- define locally to not pollute the global namespace scope
        local function reverse(tab)
            for i = 1, math.floor(#tab/2), 1 do
                tab[i], tab[#tab-i+1] = tab[#tab-i+1], tab[i]
            end
            return tab
        end
        text = reverse(text)
        -- pad text table so that we always have max_lines lines in there
        local nLinesToPad = #text - self.max_lines
        for i=1,nLinesToPad do
            table.insert(text, {text = "", level = "PRINT", name = "", time = 0, level_numeric = 1000, formatted = function() return "" end})
        end
        return text
    end,
    modifiersListener = function(self)
        -- disable text input if ctrl or cmd is pressed
        -- this is to fallback to love.keypressed when a modifier is pressed that can
        -- link to a command (like ctrl+c, ctrl+v, etc)
        self.logger:trace("modifiers", self.modifiers)
        if self.modifiers.ctrl or self.modifiers.meta then
            love.textinput = nil
        else
            love.textinput = function(character)
                self.cmd = self.cmd .. character
            end
        end
    end,
    typeKey = function (self, key_name)
        -- cmd+shift+C on mac, ctrl+shift+C on windows/linux
        if key_name == "c" and ((platform.is_mac and self.modifiers.meta and self.modifiers.shift) or (not platform.is_mac and self.modifiers.ctrl and self.modifiers.shift)) then
            local messages = self:getFilteredMessages()
            local text = ""
            for _, message in ipairs(messages) do
                text = text .. message:formatted() .. "\n"
            end
            love.system.setClipboardText(text)
            return
        end
        -- cmd+C on mac, ctrl+C on windows/linux
        if key_name == "c" and ((platform.is_mac and self.modifiers.meta) or (not platform.is_mac and self.modifiers.ctrl)) then
            if self.cmd:sub(3) == "" then
                -- do nothing if the buffer is empty
                return
            end
            love.system.setClipboardText(self.cmd:sub(3))
            return
        end
        -- cmd+V on mac, ctrl+V on windows/linux
        if key_name == "v" and ((platform.is_mac and self.modifiers.meta) or (not platform.is_mac and self.modifiers.ctrl)) then
            self.cmd = self.cmd .. love.system.getClipboardText()
            return
        end
        if key_name == "escape" then
            -- close the console
            self:toggle()
            return
        end
        -- Delete the current command, on mac it's cmd+backspace
        if key_name == "delete" or (platform.is_mac and self.modifiers.meta and key_name == "backspace") then
            self.cmd = "> "
            return
        end
        if key_name == "end" or (platform.is_mac and key_name == "right" and self.modifiers.meta) then
            -- move text to the most recent (bottom)
            self.start_line_offset = self.max_lines
            return
        end
        if key_name == "home" or (platform.is_mac and key_name == "left" and self.modifiers.meta) then
            -- move text to the oldest (top)
            local messages = self:getFilteredMessages()
            self.start_line_offset = self.max_lines - #messages
            return
        end
        if key_name == "pagedown" or (platform.is_mac and key_name == "down" and self.modifiers.meta) then
            -- move text down by max_lines
            self.start_line_offset = math.min(self.start_line_offset + self.max_lines, self.max_lines)
            return
        end
        if key_name == "pageup"  or (platform.is_mac and key_name == "up" and self.modifiers.meta) then
            -- move text up by max_lines
            local messages = self:getFilteredMessages()
            self.start_line_offset = math.max(self.start_line_offset - self.max_lines, self.max_lines - #messages)
            return
        end
        if key_name == "up" then
            -- move to the next command in the history (in reverse order of insertion)
            self.history_index = math.min(self.history_index + 1, #self.command_history)
            if self.history_index == 0 then
                self.cmd = "> "
                return
            end
            self.cmd = "> " .. self.command_history[#self.command_history - self.history_index + 1]
            return
        end
        if key_name == "down" then
            -- move to the previous command in the history (in reverse order of insertion)
            self.history_index = math.max(self.history_index - 1, 0)
            if self.history_index == 0 then
                self.cmd = "> "
                return
            end
            self.cmd = "> " .. self.command_history[#self.command_history - self.history_index + 1]
            return
        end
        if key_name == "tab" then
            local completion = self:tryAutocomplete()
            if completion then
                -- get the last part of the console command
                local lastPart = self.cmd:match("%S+$")
                if lastPart == nil then -- cmd ends with a space, so we stop the completion
                    return
                end
                -- then replace the whole last part with the autocompleted command
                self.cmd = self.cmd:sub(1, #self.cmd - #lastPart) .. completion
            end
            return
        end
        if key_name == "lalt" or key_name == "ralt" then
            self.modifiers.alt = true
            self:modifiersListener()
            return
        end
        if key_name == "lctrl" or key_name == "rctrl" then
            self.modifiers.ctrl = true
            self:modifiersListener()
            return
        end
        if key_name == "lshift" or key_name == "rshift" then
            self.modifiers.shift = true
            self:modifiersListener()
            return
        end
        if key_name == "lgui" or key_name == "rgui" then
            -- windows key / meta / cmd key (on macos)
            self.modifiers.meta = true
            self:modifiersListener()
            return
        end
        if key_name == "backspace" then
            if #self.cmd > 2 then
                local byteoffset = utf8.offset(self.cmd, -1)
                if byteoffset then
                    -- remove the last UTF-8 character.
                    -- string.sub operates on bytes rather than UTF-8 characters, so we couldn't do string.sub(text, 1, -2).
                    self.cmd = string.sub(self.cmd, 1, byteoffset - 1)
                end
            end
            return
        end
        if key_name == "return" or key_name == "kpenter" then
            self.logger:print(self.cmd)
            local cmdName = self.cmd:sub(3)
            cmdName = cmdName:match("%S+")
            if cmdName == nil then
                return
            end
            local args = {}
            local argString = self.cmd:sub(3 + #cmdName + 1)
            if argString then
                for arg in argString:gmatch("%S+") do
                    table.insert(args, arg)
                end
            end
            local success = false
            if _REGISTERED_COMMANDS[cmdName] then
                success = _REGISTERED_COMMANDS[cmdName].call(args)
            else
                self.logger:error("Command not found: " .. cmdName)
            end
            if success then
                -- only add the command to the history if it was successful
                self:addToHistory(self.cmd:sub(3))
            end

            self.cmd = "> "
            return
        end
    end,
    addToHistory = function(self, command)
        if command == nil or command == "" then
            return
        end
        table.insert(self.command_history, command)
        self.history_index = 0
        local success, errormsg = love.filesystem.append(self.history_path, command .. "\n")
        if not success then
            self.logger:warn("Error appending ", command, " to history file: ", errormsg)
            success, errormsg = love.filesystem.write(self.history_path, command .. "\n")
            if not success then
                self.logger:error("Error writing to history file: ", errormsg)
            end
        end
    end,
}

table.insert(mods,
    {
        mod_id = "console_cals",
        name = "Console Calculator",
        version = "0.1.10",
        author = "me",
        description = {
            "Press F2 to open/close the console",
            "Use command `help` for a list of ",
            "available commands and shortcuts",
        },
        enabled = true,
        on_error = function(message)
            console.logger:error("Error: ", message)
            -- on error, write all messages to a file
            love.filesystem.write("dev_console.log", "")
            for i, message in ipairs(ALL_MESSAGES) do
                love.filesystem.append("dev_console.log", message:formatted(true) .. "\n")
            end
        end,
        on_enable = function()
            console.logger:debug("Dev Console enabled")
            contents, size = love.filesystem.read(console.history_path)
            if contents then
                console.logger:trace("History file size", size)
                for line in contents:gmatch("[^\r\n]+") do
                    if line and line ~= "" then
                        table.insert(console.command_history, line)
                    end
                end
            end

            registerCommand(
                "help",
                function()
                    console.logger:print("Available commands:")
                    for name, cmd in pairs(_REGISTERED_COMMANDS) do
                        if cmd.desc then
                            console.logger:print(name .. ": " .. cmd.desc)
                        end
                    end
                    return true
                end,
                "Prints a list of available commands",
                function(current_arg)
                    local completions = {}
                    for name, _ in pairs(_REGISTERED_COMMANDS) do
                        if name:find(current_arg, 1, true) == 1 then
                            table.insert(completions, name)
                        end
                    end
                    return completions
                end,
                "Usage: help <command>"
            )

            registerCommand(
                "shortcuts",
                function()
                    console.logger:print("Available shortcuts:")
                    console.logger:print("F2: Open/Close the console")
                    console.logger:print("F4: Toggle debug mode")
                    if platform.is_mac then
                        console.logger:print("Cmd+C: Copy the current command to the clipboard.")
                        console.logger:print("Cmd+Shift+C: Copies all messages to the clipboard")
                        console.logger:print("Cmd+V: Paste the clipboard into the current command")
                    else
                        console.logger:print("Ctrl+C: Copy the current command to the clipboard.")
                        console.logger:print("Ctrl+Shift+C: Copies all messages to the clipboard")
                        console.logger:print("Ctrl+V: Paste the clipboard into the current command")
                    end
                    return true
                end,
                "Prints a list of available shortcuts",
                function(current_arg)
                    return nil
                end,
                "Usage: shortcuts"
            )

            registerCommand(
                "history",
                function()
                    console.logger:print("Command history:")
                    for i, cmd in ipairs(console.command_history) do
                        console.logger:print(i .. ": " .. cmd)
                    end
                    return true
                end,
                "Prints the command history"
            )

            registerCommand(
                "clear",
                function()
                    ALL_MESSAGES = {}
                    return true
                end,
                "Clear the console"
            )

            registerCommand(
                "exit",
                function()
                    console:toggle()
                    return true
                end,
                "Close the console"
            )

            registerCommand(
                "give",
                function()
                    console.logger:error("Give command not implemented yet")
                    return false
                end,
                "Give an item to the player"
            )

            registerCommand(
                "money",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_dollars(amount, true)
                                console.logger:info("Added " .. amount .. " money to the player")
                            elseif args[1] == "remove" then
                                ease_dollars(-amount, true)
                                console.logger:info("Removed " .. amount .. " money from the player")
                            elseif args[1] == "set" then
                                local currentMoney = G.GAME.dollars
                                local diff = amount - currentMoney
                                ease_dollars(diff, true)
                                console.logger:info("Set player money to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                            end
                        else
                            console.logger:error("Invalid amount")
                            return false
                        end
                    else
                        console.logger:warn("Usage: money <add/remove/set> <amount>")
                        return false
                    end
                    return true
                end,
                "Change the player's money",
                function (current_arg)
                    local subcommands = {"add", "remove", "set"}
                    for i, v in ipairs(subcommands) do
                        if v:find(current_arg, 1, true) == 1 then
                            return {v}
                        end
                    end
                    return nil
                end
            )

            registerCommand(
                "discards",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_discard(amount, true)
                                console.logger:info("Added " .. amount .. " discards to the player")
                            elseif args[1] == "remove" then
                                ease_discard(-amount, true)
                                console.logger:info("Removed " .. amount .. " discards from the player")
                            elseif args[1] == "set" then
                                local currentDiscards = G.GAME.current_round.discards_left
                                local diff = amount - currentDiscards
                                ease_discard(diff, true)
                                console.logger:info("Set player discards to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                                return false
                            end
                        else
                            console.logger:error("Invalid amount")
                            return false
                        end
                    else
                        console.logger:warn("Usage: discards <add/remove/set> <amount>")
                        return false
                    end
                    return true
                end,
                "Change the player's discards",
                function (current_arg)
                    local subcommands = {"add", "remove", "set"}
                    for i, v in ipairs(subcommands) do
                        if v:find(current_arg, 1, true) == 1 then
                            return {v}
                        end
                    end
                    return nil
                end
            )

            registerCommand(
                "hands",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_hands_played(amount, true)
                                console.logger:info("Added " .. amount .. " hands to the player")
                            elseif args[1] == "remove" then
                                ease_hands_played(-amount, true)
                                console.logger:info("Removed " .. amount .. " hands from the player")
                            elseif args[1] == "set" then
                                local currentHands = G.GAME.current_round.hands_left
                                local diff = amount - currentHands
                                ease_hands_played(diff, true)
                                console.logger:info("Set player hands to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                                return false
                            end
                        else
                            console.logger:error("Invalid amount")
                            return false
                        end
                    else
                        console.logger:warn("Usage: hands <add/remove/set> <amount>")
                        return false
                    end
                    return true
                end,
                "Change the player's remaining hands",
                function (current_arg)
                    local subcommands = {"add", "remove", "set"}
                    for i, v in ipairs(subcommands) do
                        if v:find(current_arg, 1, true) == 1 then
                            return {v}
                        end
                    end
                    return nil
                end
            )
            -----------
            -- Calc command:
            --  Took the bulk of this code from state_events.evaluate_play, which takes cards from play and scores them
            --  A few changes made include setting up an "artificial play" area (candidatePlayed) to evaluate, as when a card is "played", it is 
            -- first moved into the play area (and out of the and).
            -- Therefore, an artificial hand of the non highlighted cards was also created (unhighlightedHand)
            -- Additionally, we have to remove all code that alters a joker (Square, Supernove, etc.), card (Glass), hand (upgrading), or money.
            -- For example do not increment Supernove, but add an additional counter to the multi_mod to account for its increment.
            -- All UI code elements were removed, including delay, card_eval_status_text, mod_percent, update_hand_text, etc.
            -- Finally, all event triggers (mostly UI) were removed.
            -- 
            -- TODO: Need to account for objects upgrades which upgrade when they area, but not apply them to the object self.  Supernova is handled, but there are more.
            -----------
            registerCommand(
                "calc",
                function(args)
                    if #G.hand.highlighted == 0 then return true end
                    
                    console.logger:info("hello")
                    -- first set our candidate hand and unhighlightedHand
                    -- this is necesary, bc normally the cards are removed from the hand before being played
                    -- we do not have that luxury, therefore we must setup an artificial hand and played hand
                    local candidatePlayed = G.hand.highlighted
                    local unhighlightedHand = {}
                    for i=1, #G.hand.cards do
                        if not G.hand.cards[i].highlighted then table.insert(unhighlightedHand, G.hand.cards[i]) end
                    end
                
                    local text,disp_text,poker_hands,scoring_hand,non_loc_disp_text = G.FUNCS.get_poker_hand_info(G.hand.highlighted)

                    local pures = {}
                    for i=1, #candidatePlayed do
                        if next(find_joker('Splash')) then
                            scoring_hand[i] = candidatePlayed[i]
                        else
                            if candidatePlayed[i].ability.effect == 'Stone Card' then
                                local inside = false
                                for j=1, #scoring_hand do
                                    if scoring_hand[j] == candidatePlayed[i] then
                                        inside = true
                                    end
                                end
                                if not inside then table.insert(pures, candidatePlayed[i]) end
                            end
                        end
                    end

                    for i=1, #pures do
                        table.insert(scoring_hand, pures[i])
                    end

                    console.logger:info(string.format("a total of %d cards will be scored", #scoring_hand))

                    table.sort(scoring_hand, function (a, b) return a.T.x < b.T.x end )
                    -- TODO bring in boss debuffs
                    -- if not G.GAME.blind:debuff_hand(G.play.cards, poker_hands, text) then
                    -- this code get the current multiplier for the hand

                    -- NOTE - this gets the multiplier of the hand being played, i.e. flush, straight, etc.
                    -- this does NOT include the cards.  "hand_chips" does not include the value of the played cards (Ace, 3, king, etc.)
                    local mult = mod_mult(G.GAME.hands[text].mult)
                    local hand_chips = mod_chips(G.GAME.hands[text].chips)


                    -- this is just for the blind "The Flint" which halves your chips
                    local modded = false
                    mult, hand_chips, modded = G.GAME.blind:modify_hand(candidatePlayed, poker_hands, text, mult, hand_chips)
                    
                    -- this is specifically for the "Rich get Richer" achievement
                    -- for now disable
                    -- hand_chips = mod_chips(hand_chips)
                    
                     --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    --Played Card Effects
                    --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    for i=1, #scoring_hand do
                        --add cards played to list
                        -- if scoring_hand[i].ability.effect ~= 'Stone Card' then 
                        --     G.GAME.cards_played[scoring_hand[i].base.value].total = G.GAME.cards_played[scoring_hand[i].base.value].total + 1
                        --     G.GAME.cards_played[scoring_hand[i].base.value].suits[scoring_hand[i].base.suit] = true 
                        -- end
                        --if card is debuffed
                        -- if scoring_hand[i].debuff then
                        --     G.GAME.blind.triggered = true
                        --     G.E_MANAGER:add_event(Event({
                        --         trigger = 'immediate',
                        --         func = (function() G.HUD_blind:get_UIE_by_ID('HUD_blind_debuff_1'):juice_up(0.3, 0)
                        --             G.HUD_blind:get_UIE_by_ID('HUD_blind_debuff_2'):juice_up(0.3, 0)
                        --             G.GAME.blind:juice_up();return true end)
                        --     }))
                        --     card_eval_status_text(scoring_hand[i], 'debuff')
                        if true then
                            --Check for play doubling
                            local reps = {1}
                            
                            --From Red seal
                            local eval = eval_card(scoring_hand[i], {repetition_only = true,cardarea = G.play, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, repetition = true})
                            if next(eval) then 
                                for h = 1, eval.seals.repetitions do
                                    reps[#reps+1] = eval
                                end
                            end
                            --From jokers
                            for j=1, #G.jokers.cards do
                                --calculate the joker effects
                                local eval = eval_card(G.jokers.cards[j], {cardarea = G.play, full_hand =candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_card = scoring_hand[i], repetition = true})
                                if next(eval) and eval.jokers then 
                                    for h = 1, eval.jokers.repetitions do
                                        reps[#reps+1] = eval
                                    end
                                end
                            end
                            for j=1,#reps do
                                -- percent = percent + percent_delta
                                -- if reps[j] ~= 1 then
                                --     card_eval_status_text((reps[j].jokers or reps[j].seals).card, 'jokers', nil, nil, nil, (reps[j].jokers or reps[j].seals))
                                -- end
                                
                                --calculate the hand effects
                                local effects = {eval_card(scoring_hand[i], {cardarea = G.play, full_hand = candidatePlayed, scoring_hand = scoring_hand, poker_hand = text})}
                                for k=1, #G.jokers.cards do
                                    --calculate the joker individual card effects
                                    local eval = G.jokers.cards[k]:calculate_joker({cardarea = G.play, full_hand = G.play.cards, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_card = scoring_hand[i], individual = true})
                                    if eval then 
                                        table.insert(effects, eval)
                                    end
                                end
                                scoring_hand[i].lucky_trigger = nil
            
                                for ii = 1, #effects do
                                    --If chips added, do chip add event and add the chips to the total
                                    if effects[ii].chips then 
                                        -- UI effect only
                                        -- if effects[ii].card then juice_card(effects[ii].card) end
                                        hand_chips = mod_chips(hand_chips + effects[ii].chips)
                                        -- update_hand_text({delay = 0}, {chips = hand_chips})
                                        -- card_eval_status_text(scoring_hand[i], 'chips', effects[ii].chips, percent)
                                    end
            
                                    --If mult added, do mult add event and add the mult to the total
                                    if effects[ii].mult then 
                                        -- if effects[ii].card then juice_card(effects[ii].card) end
                                        mult = mod_mult(mult + effects[ii].mult)
                                        -- update_hand_text({delay = 0}, {mult = mult})
                                        -- card_eval_status_text(scoring_hand[i], 'mult', effects[ii].mult, percent)
                                    end
            
                                    --If play dollars added, add dollars to total
                                    -- if effects[ii].p_dollars then 
                                    --     if effects[ii].card then juice_card(effects[ii].card) end
                                    --     ease_dollars(effects[ii].p_dollars)
                                    --     -- card_eval_status_text(scoring_hand[i], 'dollars', effects[ii].p_dollars, percent)
                                    -- end
            
            
                                    --Any extra effects
                                    if effects[ii].extra then 
                                        -- if effects[ii].card then juice_card(effects[ii].card) end
                                        local extras = {mult = false, hand_chips = false}
                                        if effects[ii].extra.mult_mod then mult =mod_mult( mult + effects[ii].extra.mult_mod);extras.mult = true end
                                        if effects[ii].extra.chip_mod then hand_chips = mod_chips(hand_chips + effects[ii].extra.chip_mod);extras.hand_chips = true end
                                        if effects[ii].extra.swap then 
                                            local old_mult = mult
                                            mult = mod_mult(hand_chips)
                                            hand_chips = mod_chips(old_mult)
                                            extras.hand_chips = true; extras.mult = true
                                        end
                                        -- update_hand_text({delay = 0}, {chips = extras.hand_chips and hand_chips, mult = extras.mult and mult})
                                        -- card_eval_status_text(scoring_hand[i], 'extra', nil, percent, nil, effects[ii].extra)
                                    end
            
                                    --If x_mult added, do mult add event and mult the mult to the total
                                    if effects[ii].x_mult then 
                                        -- if effects[ii].card then juice_card(effects[ii].card) end
                                        mult = mod_mult(mult*effects[ii].x_mult)
                                        -- update_hand_text({delay = 0}, {mult = mult})
                                        -- card_eval_status_text(scoring_hand[i], 'x_mult', effects[ii].x_mult, percent)
                                    end
            
                                    --calculate the card edition effects
                                    if effects[ii].edition then
                                        hand_chips = mod_chips(hand_chips + (effects[ii].edition.chip_mod or 0))
                                        mult = mult + (effects[ii].edition.mult_mod or 0)
                                        mult = mod_mult(mult*(effects[ii].edition.x_mult_mod or 1))
                                        -- update_hand_text({delay = 0}, {
                                        --     chips = effects[ii].edition.chip_mod and hand_chips or nil,
                                        --     mult = (effects[ii].edition.mult_mod or effects[ii].edition.x_mult_mod) and mult or nil,
                                        -- })
                                        -- card_eval_status_text(scoring_hand[i], 'extra', nil, percent, nil, {
                                        --     message = (effects[ii].edition.chip_mod and localize{type='variable',key='a_chips',vars={effects[ii].edition.chip_mod}}) or
                                        --             (effects[ii].edition.mult_mod and localize{type='variable',key='a_mult',vars={effects[ii].edition.mult_mod}}) or
                                        --             (effects[ii].edition.x_mult_mod and localize{type='variable',key='a_xmult',vars={effects[ii].edition.x_mult_mod}}),
                                        --     chip_mod =  effects[ii].edition.chip_mod,
                                        --     mult_mod =  effects[ii].edition.mult_mod,
                                        --     x_mult_mod =  effects[ii].edition.x_mult_mod,
                                        --     colour = G.C.DARK_EDITION,
                                        --     edition = true})
                                    end
                                end
                            end
                        end
                    end

                     --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    --In hand Effects
                    --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    for i=1, unhighlightedHand do
                        local reps = {1}
                        local j = 1
                        while j <= #reps do
                            --calculate the hand effects
                            local effects = {eval_card(unhighlightedHand[i], {cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands})}
        
                            for k=1, #G.jokers.cards do
                                --calculate the joker individual card effects
                                local eval = G.jokers.cards[k]:calculate_joker({cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_card = unhighlightedHand[i], individual = true})
                                if eval then 
                                    console.logger:info(string.format("%s had an effect on a held card.", G.jokers.cards[k].ability.name))
                                    table.insert(effects, eval)
                                end
                            end
        
                            if reps[j] == 1 then 
                                --Check for hand doubling
        
                                --From Red seal
                                local eval = eval_card(unhighlightedHand[i], {repetition_only = true,cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, repetition = true, card_effects = effects})
                                if next(eval) and (next(effects[1]) or #effects > 1) then 
                                    for h  = 1, eval.seals.repetitions do
                                        reps[#reps+1] = eval
                                    end
                                end
        
                                --From Joker
                                for j=1, #G.jokers.cards do
                                    --calculate the joker effects
                                    local eval = eval_card(G.jokers.cards[j], {cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_card = unhighlightedHand[i], repetition = true, card_effects = effects})
                                    if next(eval) then 
                                        for h  = 1, eval.jokers.repetitions do
                                            reps[#reps+1] = eval
                                        end
                                    end
                                end
                            end
            
                            for ii = 1, #effects do
                                --If hold mult added, do hold mult add event and add the mult to the total
                                if effects[ii].h_mult then
                                    mult = mod_mult(mult + effects[ii].h_mult)
                                end
        
                                if effects[ii].x_mult then
                                    mult = mod_mult(mult*effects[ii].x_mult)
                                end
                            end
                            j = j +1
                        end
                    end
                    --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    --Joker Effects
                    --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
                    for i=1, #G.jokers.cards + #G.consumeables.cards do
                        local _card = G.jokers.cards[i] or G.consumeables.cards[i - #G.jokers.cards]
                        console.logger:info(_card.ability.name)
                        --calculate the joker edition effects
                        local edition_effects = eval_card(_card, {cardarea = G.jokers, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, edition = true})
                        if edition_effects.jokers then
                            console.logger:info("edition effects")
                            console.logger:info(edition_effects.jokers.chip_mod)
                            console.logger:info(edition_effects.jokers.mult_mod)
                            -- console.logger:info(string.format("%s added %d chips and %d mult from edition effects", _card.ability.name, edition_effects.jokers.chip_mod, edition_effects.jokers.mult_mod))
                            edition_effects.jokers.edition = true
                            if edition_effects.jokers.chip_mod then
                                hand_chips = mod_chips(hand_chips + edition_effects.jokers.chip_mod)

                            end
                            if edition_effects.jokers.mult_mod then
                                mult = mod_mult(mult + edition_effects.jokers.mult_mod)
                            end
                        end
            
                        --calculate the joker effects
                        local effects = eval_card(_card, {cardarea = G.jokers, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, joker_main = true})
            
                        --Any Joker effects
                        if effects.jokers then 
                            local extras = {mult = false, hand_chips = false}
                            console.logger:info("local effects")
                            -- since supernova increments before effect, we need to do this manually
                            if _card.ability.name == "Supernova" then effects.jokers.mult_mod = effects.jokers.mult_mod + 1 end

                            console.logger:info(effects.jokers.chip_mod)
                            console.logger:info(effects.jokers.mult_mod)

                            if effects.jokers.mult_mod then mult = mod_mult(mult + effects.jokers.mult_mod);extras.mult = true end
                            if effects.jokers.chip_mod then hand_chips = mod_chips(hand_chips + effects.jokers.chip_mod);extras.hand_chips = true end
                            if effects.jokers.Xmult_mod then mult = mod_mult(mult*effects.jokers.Xmult_mod);extras.mult = true  end
                        end
            
                        --Joker on Joker effects
                        for _, v in ipairs(G.jokers.cards) do
                            local effect = v:calculate_joker{full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_joker = _card}
                            if effect then
                                console.logger:info("joker on joker effects")
                                console.logger:info(effect.jokers.chip_mod)
                                console.logger:info(effect.jokers.mult_mod)
                                local extras = {mult = false, hand_chips = false}
                                if effect.mult_mod then mult = mod_mult(mult + effect.mult_mod);extras.mult = true end
                                if effect.chip_mod then hand_chips = mod_chips(hand_chips + effect.chip_mod);extras.hand_chips = true end
                                if effect.Xmult_mod then mult = mod_mult(mult*effect.Xmult_mod);extras.mult = true  end
                            end
                        end
            
                        if edition_effects.jokers then
                            console.logger:info("multi edition")
                            console.logger:info(edition_effects.jokers.x_mult_mod)
                            if edition_effects.jokers.x_mult_mod then
                                mult = mod_mult(mult*edition_effects.jokers.x_mult_mod)
                            end
                        end
                    end
                    console.logger:info(string.format("non-multi chip count is:  %d", hand_chips))
                    console.logger:info(string.format("total multiplier is :  %d", mult))
                    console.logger:info(string.format("total chip value is :  %d", mult * hand_chips))



                    return true
                end,
                "Change the player's remaining hands",
                function (current_arg)
                    local subcommands = {"add", "remove", "set"}
                    for i, v in ipairs(subcommands) do
                        if v:find(current_arg, 1, true) == 1 then
                            return {v}
                        end
                    end
                    return nil
                end
            )

        end,
        on_disable = function()
        end,
        on_key_pressed = function (key_name)
            if key_name == "f2" then
                console:toggle()
                return true
            end
            if console.is_open then
                console:typeKey(key_name)
                return true
            end

            if key_name == "f4" then
                G.DEBUG = not G.DEBUG
                if G.DEBUG then
                    console.logger:info("Debug mode enabled")
                else
                    console.logger:info("Debug mode disabled")
                end
            end
            return false
        end,
        on_post_render = function ()
            console.max_lines = math.floor(love.graphics.getHeight() / LINE_HEIGHT) - 5  -- 5 lines of bottom padding
            if console.is_open then
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                for i, message in ipairs(console:getMessagesToDisplay()) do
                    r, g, b = console:getMessageColor(message)
                    love.graphics.setColor(r, g, b, 1)
                    love.graphics.print(message:formatted(), 10, 10 + i * 20)
                end
                love.graphics.setColor(1, 1, 1, 1) -- white
                love.graphics.print(console.cmd, 10, love.graphics.getHeight() - 30)
            end
        end,
        on_key_released = function (key_name)
            if key_name == "capslock" then
                console.modifiers.capslock = not console.modifiers.capslock
                console:modifiersListener()
                return
            end
            if key_name == "scrolllock" then
                console.modifiers.scrolllock = not console.modifiers.scrolllock
                console:modifiersListener()
                return
            end
            if key_name == "numlock" then
                console.modifiers.numlock = not console.modifiers.numlock
                console:modifiersListener()
                return
            end
            if key_name == "lalt" or key_name == "ralt" then
                console.modifiers.alt = false
                console:modifiersListener()
                return false
            end
            if key_name == "lctrl" or key_name == "rctrl" then
                console.modifiers.ctrl = false
                console:modifiersListener()
                return false
            end
            if key_name == "lshift" or key_name == "rshift" then
                console.modifiers.shift = false
                console:modifiersListener()
                return false
            end
            if key_name == "lgui" or key_name == "rgui" then
                console.modifiers.meta = false
                console:modifiersListener()
                return false
            end
            return false
        end,
        on_mouse_pressed = function(x, y, button, touches)
            if console.is_open then
                return true  -- Do not press buttons through the console, this cancels the event
            end
        end,
        on_mouse_released = function(x, y, button)
            if console.is_open then
                return true -- Do not release buttons through the console, this cancels the event
            end
        end,
    }
)