local calculator = {
    debug = false,
    renderScore = true,
    currentScore = 0,
    currentHighlighted = {},
    -----------
            -- calculateScore command:
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
            -- TODO: break this up into multiple functions
            -- TODO: add tests (lol)
            -----------
    calculateScore = function(self)
        -- could probably short circuit, but idk Lua
        if  G.hand == nil  then return true end
        if #G.hand.highlighted == 0 then return true end
        
        -- first set our candidate hand and unhighlightedHand
        -- this is necesary, bc normally the cards are removed from the hand before being played
        -- we do not have that luxury, therefore we must setup an artificial hand and played hand
        local candidatePlayed = G.hand.highlighted
        -- self.currentHighlighted = candidatePlayed
        local unhighlightedHand = {}
        self.currentHighlighted = {}
        for i=1, #G.hand.cards do
            if not G.hand.cards[i].highlighted then table.insert(unhighlightedHand, G.hand.cards[i]) end

            if G.hand.cards[i].highlighted then
                table.insert(self.currentHighlighted, true)
            else
                table.insert(self.currentHighlighted, false)
            end
        end
    
        local text,disp_text,poker_hands,scoring_hand,non_loc_disp_text = G.FUNCS.get_poker_hand_info(candidatePlayed)

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

        table.sort(scoring_hand, function (a, b) return a.T.x < b.T.x end )
        -- TODO bring in boss debuffs
        -- if not G.GAME.blind:debuff_hand(G.play.cards, poker_hands, text) then
        -- this code get the current multiplier for the hand

        -- NOTE - this gets the multiplier of the hand being played, i.e. flush, straight, etc.
        -- this does NOT include the cards.  "hand_chips" does not include the value of the played cards (Ace, 3, king, etc.)
        if  G.GAME == nil or G.GAME.hands == nil or text == nil then
            self.currentScore = "No Hnds?"
            return
        end
        local x = G.GAME.hands[text].mult
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
                            hand_chips = mod_chips(hand_chips + effects[ii].chips)
                        end

                        --If mult added, do mult add event and add the mult to the total
                        if effects[ii].mult then 
                            mult = mod_mult(mult + effects[ii].mult)
                        end


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
                        end
                    end
                end
            end
        end

        --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
        --In hand Effects
        --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
        for i=1, #unhighlightedHand do
            local reps = {1}
            local j = 1
            while j <= #reps do
                --calculate the hand effects
                local effects = {eval_card(unhighlightedHand[i], {cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands})}

                for k=1, #G.jokers.cards do
                    --calculate the joker individual card effects
                    local eval = G.jokers.cards[k]:calculate_joker({cardarea = G.hand, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_card = unhighlightedHand[i], individual = true})
                    if eval then 
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
            --calculate the joker edition effects
            local edition_effects = eval_card(_card, {cardarea = G.jokers, full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, edition = true})
            if edition_effects.jokers then
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
                -- since supernova increments before effect, we need to do this manually
                if _card.ability.name == "Supernova" then effects.jokers.mult_mod = effects.jokers.mult_mod + 1 end

                if effects.jokers.mult_mod then mult = mod_mult(mult + effects.jokers.mult_mod);extras.mult = true end
                if effects.jokers.chip_mod then hand_chips = mod_chips(hand_chips + effects.jokers.chip_mod);extras.hand_chips = true end
                if effects.jokers.Xmult_mod then mult = mod_mult(mult*effects.jokers.Xmult_mod);extras.mult = true  end
            end

            --Joker on Joker effects
            for _, v in ipairs(G.jokers.cards) do
                local effect = v:calculate_joker{full_hand = candidatePlayed, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_joker = _card}
                if effect then
                    local extras = {mult = false, hand_chips = false}
                    if effect.mult_mod then mult = mod_mult(mult + effect.mult_mod);extras.mult = true end
                    if effect.chip_mod then hand_chips = mod_chips(hand_chips + effect.chip_mod);extras.hand_chips = true end
                    if effect.Xmult_mod then mult = mod_mult(mult*effect.Xmult_mod);extras.mult = true  end
                end
            end

            if edition_effects.jokers then
                if edition_effects.jokers.x_mult_mod then
                    mult = mod_mult(mult*edition_effects.jokers.x_mult_mod)
                end
            end
        end

        self.currentScore =  mult * hand_chips
    end,

    -- Idk if I know how code works anymore.  Originally tried to go item for item in previous hand vs current hand,
    -- but for some reason those comparisons kept coming up false, even though they were the same (see the debugging)
    -- Finally gave up on that and realized that you can't change two cards in a single render, so as long as the count matches
    -- the highlighted can be assumed to match.
    -- Technically this check is not necessary, but it's hugely wastful to calculate the score every frame, so I added it.
    -- Notice that when everything is first loaded, nil is set for all the handHighlighted values, but once you highlight and return,
    -- it gets changed to false. 
    -- Anyway, this appears to work
    -- TODO: figure out why the other didnt work
    -- TODO: cleanup and set ONLY the count in calculateScore function
    -- TODO: Test?
    highlightedHasChanged = function(self)
        if self.currentHighlighted == nil then return true end
        self:logIfDebugOn(#G.hand.cards, 100, 200 )
        self:logIfDebugOn(#self.currentHighlighted, 200, 200 )
        local handHighlightedCount, previousHighlightedCount = 0,0
        for j=1, #G.hand.cards do
            if G.hand.cards[j].highlighted then
                self:logIfDebugOn("true", 400, 50 + j * 25)
                handHighlightedCount = 1 + handHighlightedCount
            elseif G.hand.cards[j].highlighted == nil then
                self:logIfDebugOn("nil", 400, 50 + j * 25)
            else 
                self:logIfDebugOn("false", 400, 50 + j * 25)
            end
        end

        for j=1, #self.currentHighlighted do
            if self.currentHighlighted[j] then
                self:logIfDebugOn("true", 500, 50 + j * 25)
                previousHighlightedCount = 1 + previousHighlightedCount
            else
                self:logIfDebugOn("false", 500, 50 + j * 25)
            end
        end

        self:logIfDebugOn(previousHighlightedCount, 200, 50)
        self:logIfDebugOn(handHighlightedCount, 220, 50)
        if #G.hand.cards ~= #self.currentHighlighted then return true end
        return handHighlightedCount ~= previousHighlightedCount
    end,

    logIfDebugOn = function(self, text, x, y)
        if self.debug then  love.graphics.print(text, x, y) end
    end,


    -- Change the integer to a pretty string with commas.  Thanks Chat GPT!
    formatNumberWithCommas = function(self, number)
        local formatted = tostring(number)
        local k
    
        while true do  
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then
                break
            end
        end
    
        return formatted
    end
}

table.insert(mods,
        {
            mod_id = "simple_calc",
            name = "Simple Calculator",
            version = "0.1",
            author = "csmeal",
            description = {
                "Press 'C' to show and hide the current calulation of your hand"
            },
            enabled = true,
            on_enable = function()
                _RELEASE_MODE = false
            end,
            on_disable = function()

            end,
            on_key_pressed = function(key_name)
                if key_name == "c" then
                    calculator.renderScore = not calculator.renderScore
                end

                return false
            end,
            on_post_render = function()
                if  G.hand == nil  then return end
                if #G.hand.highlighted == 0 then return end
                if not calculator.renderScore then return end
                local has_changed = calculator:highlightedHasChanged()
                if has_changed then calculator:calculateScore() end

                love.graphics.print(string.format("Current played hand scores: %s", calculator:formatNumberWithCommas(calculator.currentScore)), 10, 32) 
                if has_changed then calculator:logIfDebugOn('has changed', 100, 350) end
                if not has_changed then calculator:logIfDebugOn('NO CHANGE', 100, 350) end

                
            end,
        }
)
