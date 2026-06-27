#==============================================================================
# ELO Tournament — headless boot hook
#
# When ELO_TOURNAMENT is set, replaces the title screen with a direct jump
# into the tournament runner, then exits the process once it's done. Normal
# play (ELO_TOURNAMENT unset) is completely untouched.
#==============================================================================
if ENV["ELO_TOURNAMENT"]
    # pbEndOfBattle unconditionally writes a full per-random-draw call-stack
    # log to disk on every single battle, regardless of save_battle. Harmless
    # for one-off benchmark runs; pure waste at hundreds-of-thousands-of-
    # battles tournament scale.
    module PokeBattle_BattleRecorder
        def saveRandomLog(path); end
    end

    # pbPrintException (used by both logonerr's per-move recovery and
    # pbCriticalCode's top-level handler) prints the error and then waits in
    # an Input.update loop for a Ctrl press, and on Windows that print() can
    # surface as a real modal dialog -- silently stalling what's supposed to
    # be an unattended run until someone dismisses it by hand. Errors still
    # need to reach errorlog.txt (the tournament's error-detection depends on
    # it), so this keeps that half verbatim and drops the interactive half.
    def pbPrintException(e)
        emessage = if $EVENTHANGUPMSG && $EVENTHANGUPMSG != ""
            msg = $EVENTHANGUPMSG
            $EVENTHANGUPMSG = nil
            msg
        else
            pbGetExceptionMessage(e)
        end
        message = "[Pokémon Essentials version #{Essentials::VERSION || ""}]\r\n"
        gameVersion = (Settings::GAME_VERSION rescue "UNKNOWN")
        message += "[Game version #{gameVersion}]\r\n"
        message += "#{Essentials::ERROR_TEXT}\r\n"
        message += "Exception: #{e.class}\r\n"
        message += "Message: #{emessage}\r\n"
        message += "\r\nBacktrace:\r\n"
        btrace = ""
        if e.backtrace
            maxlength = $INTERNAL ? 25 : 10
            e.backtrace[0, maxlength].each { |i| btrace += "#{i}\r\n" }
        end
        btrace.gsub!(/Section(\d+)/) { $RGSS_SCRIPTS[$1.to_i][1] } rescue nil
        message += btrace
        errorlog = "errorlog.txt"
        errorlog = RTP.getSaveFileName("errorlog.txt") if (Object.const_defined?(:RTP) rescue false)
        File.open(errorlog, "ab") do |f|
            f.write("\r\n=================\r\n\r\n[#{Time.now}]\r\n")
            f.write(message)
        end
    end

    # amuletActivates is the curse-policy "boss power activates" announcement
    # (background sprite, sound effects, message window) -- every curse
    # script calls it purely for presentation before applying its actual
    # mechanical effect (curses_array.push, pbStartWeather, etc.) as a
    # separate statement. It manipulates real scene sprites/databoxes that
    # don't exist on the no-UI benchmark scene, crashing every CURSE_*
    # trainer's battles. Skipping it entirely in benchmark mode leaves the
    # mechanical effects (checked elsewhere via curses_array) untouched.
    class PokeBattle_Battle
        alias_method :amuletActivates_preTournament, :amuletActivates
        def amuletActivates(curseName, explanation = nil, noAmulet = false)
            return if $aiBenchmarkRunning
            amuletActivates_preTournament(curseName, explanation, noAmulet)
        end
    end

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
