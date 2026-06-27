#==============================================================================
# ELO Tournament — headless boot hook
#
# When ELO_TOURNAMENT is set, replaces the title screen with a direct jump
# into the tournament runner, then exits the process once it's done. Normal
# play (ELO_TOURNAMENT unset) is completely untouched.
#==============================================================================
if ENV["ELO_TOURNAMENT"]
    # On a fresh checkout with no save file, Game.set_up_system blocks on a
    # language-selection prompt before Main ever reaches pbCallTitle. Default
    # straight to the first configured language so first-time unattended runs
    # don't stall waiting for input.
    def pbChooseLanguage
        return 0
    end

    def pbCallTitle
        SaveData.load_new_game_values
        # Trainers with the MATCH_LEVEL_CAP policy scale to the current story
        # level cap, which is normally raised by map events as the player
        # progresses. We never enter a map, so it would otherwise sit at its
        # Game_Variables.new default (0), an invalid Pokemon level. Max it out
        # so these trainers fight at full strength instead of crashing.
        setLevelCap(MAX_LEVEL_CAP, false)
        EloTournament.run!
        return nil
    end
end
