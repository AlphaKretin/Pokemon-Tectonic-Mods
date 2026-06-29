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

    # pbStartOfRoundPhase runs exactly once per round, right at the top of
    # pbBattleLoop -- a clean per-round heartbeat. A 100-round battle that's
    # genuinely just slow (e.g. two heavy-sustain teams that can't finish
    # each other off) can legitimately take 140s+, well past what looked
    # like a safe stall threshold; but a turn that's actually stuck hangs
    # immediately. Writing the current round number lets an external
    # watchdog tell those two cases apart instead of conflating them into
    # one whole-battle timer.
    class PokeBattle_Battle
        alias_method :pbStartOfRoundPhase_preTournament, :pbStartOfRoundPhase
        def pbStartOfRoundPhase
            if $aiBenchmarkRunning
                path = ENV["ELO_TURN_HEARTBEAT_PATH"] || "Analysis/elo_turn_heartbeat.json"
                File.open(path, "w") { |f| f.write("{\"turn\":#{@turnCount},\"updated_at\":\"#{Time.now}\"}") }
            end
            pbStartOfRoundPhase_preTournament
        end
    end

    # On a fresh checkout with no save file, Game.set_up_system blocks on a
    # language-selection prompt before Main ever reaches pbCallTitle. Default
    # straight to the first configured language so first-time unattended runs
    # don't stall waiting for input.
    def pbChooseLanguage
        return 0
    end

    # Temporary diagnostic (ELO_PROFILE_TIMING): wraps the four per-round
    # battle phases plus the two AI sub-steps with wall-clock timing.
    if ENV["ELO_PROFILE_TIMING"]
        class PokeBattle_Battle
            PROFILE_TIMINGS = Hash.new(0.0)
            PROFILE_CALLS = Hash.new(0)
            %i[pbCommandPhase pbAttackPhase pbEndOfRoundPhase pbStartOfRoundPhase].each do |phase|
                alias_method :"#{phase}_preProfile", phase
                define_method(phase) do |*args, **kwargs|
                    t0 = Time.now
                    ret = send(:"#{phase}_preProfile", *args, **kwargs)
                    PROFILE_TIMINGS[phase] += Time.now - t0
                    PROFILE_CALLS[phase] += 1
                    ret
                end
            end
        end

        class PokeBattle_AI
            %i[pbEnemyShouldWithdraw? pbGetBestTrainerMoveChoices estimateSwitchScoreCeiling].each do |phase|
                alias_method :"#{phase}_preProfile", phase
                define_method(phase) do |*args, **kwargs|
                    t0 = Time.now
                    ret = send(:"#{phase}_preProfile", *args, **kwargs)
                    PokeBattle_Battle::PROFILE_TIMINGS[phase] += Time.now - t0
                    PokeBattle_Battle::PROFILE_CALLS[phase] += 1
                    ret
                end
            end
        end

        def dump_profile_timing!
            File.open("Analysis/profile_timing.txt", "a") do |f|
                f.puts("=== battle ===")
                PokeBattle_Battle::PROFILE_TIMINGS.each do |phase, total|
                    calls = PokeBattle_Battle::PROFILE_CALLS[phase]
                    f.puts("#{phase}: #{total.round(3)}s over #{calls} calls (#{(total / calls * 1000).round(2)}ms/call)")
                end
            end
        end
    end

    def pbCallTitle
        # A "debug" launch recompiles Plugins into Data/PluginScripts.rxdata
        # before Main ever reaches pbCallTitle, so just reaching this point
        # at all means that's already done. Used by setup_shards.ps1
        # -Recompile to detect "compile finished" via a marker file
        # existing instead of comparing file timestamps across PowerShell/
        # bash, which kept disagreeing on UTC vs. local time and produced
        # several false "done" reads earlier this session.
        if ENV["ELO_COMPILE_ONLY"]
            File.open("Analysis/compile_done.txt", "w") { |f| f.write(Time.now.to_s) }
            exit
        end

        SaveData.load_new_game_values
        # Trainers with the MATCH_LEVEL_CAP policy scale to the current story
        # level cap, which is normally raised by map events as the player
        # progresses. We never enter a map, so it would otherwise sit at its
        # Game_Variables.new default (0), an invalid Pokemon level. Max it out
        # so these trainers fight at full strength instead of crashing.
        setLevelCap(MAX_LEVEL_CAP, false)
        if ENV["ELO_TEST_SINGLE_PAIRING"]
            EloTournament.testSinglePairing!
            dump_profile_timing! if ENV["ELO_PROFILE_TIMING"]
        elsif ENV["ELO_SAVE_REPLAY"]
            EloTournament.saveReplay!
        elsif ENV["ELO_RUN_BRACKET"]
            EloTournament.runBracket!
        elsif ENV["ELO_DUMP_TRAINER_CARD_DATA"]
            EloTournament.dumpTrainerCardData!
        else
            EloTournament.run!
        end
        return nil
    end
end
