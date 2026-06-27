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
        EloTournament.run!
        return nil
    end
end
