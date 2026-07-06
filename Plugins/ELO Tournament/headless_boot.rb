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
    #
    # Skipped entirely for ELO_WATCH_REPLAY_NAME (the viewer's Watch tab):
    # there a human is already sitting in front of the game watching one
    # replay at a time, so the engine's own interactive modal is exactly
    # what's wanted -- it pauses the replay on each error instead of letting
    # errorlog.txt get spammed by a batch of them in a row, which is the
    # whole point when tracking down a VS Recorder desync one error at a
    # time. Leaving this undefined here means the original (non-headless)
    # pbPrintException stays in effect.
    unless ENV["ELO_WATCH_REPLAY_NAME"]
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

    # Temporary diagnostic (ELO_TEST_RNG_TRACE=path): logs every pbRandom/
    # pbAIRandom draw as "index\tsource\targ\tresult" to the given path.
    # Used to diff the exact RNG sequence between two platform builds for
    # an identical srand(seed) run -- if the traces match bit-for-bit but
    # the battle result still diverges, the RNG itself isn't the cause.
    #
    # Patches pbRandom/pbAIRandom rather than Kernel#rand directly: an
    # earlier attempt aliased Kernel#rand itself and logged zero calls
    # despite a normal battle running to completion with no errors --
    # mkxp-z's Ruby runtime apparently doesn't dispatch bare rand() through
    # a method a normal alias_method can intercept.
    #
    # Patches PokeBattle_BattleRecorder#pbRandom specifically, not
    # PokeBattle_Battle#pbRandom: AIBenchmark.runBattle (what
    # testSinglePairing!/testBatchPairings! actually call) instantiates
    # PokeBattle_TectonicRecordedBattle, which `include`s
    # PokeBattle_BattleRecorder -- that module's own pbRandom (recording
    # each draw into @random for replay) sits above PokeBattle_Battle in
    # the ancestor chain and shadows it completely, which is why patching
    # the base class first logged nothing.
    def install_rng_trace!
        Kernel.instance_variable_set(:@rng_trace_n, 0)
        f = File.open(ENV["ELO_TEST_RNG_TRACE"], "w")
        f.sync = true
        Kernel.instance_variable_set(:@rng_trace_file, f)

        def log_rng_trace!(source, arg, result, call_site)
            n = Kernel.instance_variable_get(:@rng_trace_n) + 1
            Kernel.instance_variable_set(:@rng_trace_n, n)
            Kernel.instance_variable_get(:@rng_trace_file).puts("#{n}\t#{source}\t#{arg.inspect}\t#{result}\t#{call_site}")
        end

        PokeBattle_BattleRecorder.class_eval do
            alias_method :pbRandom_preTrace, :pbRandom
            define_method(:pbRandom) do |x|
                call_site = caller_locations(1, 20)&.map(&:to_s)&.join(" | ")
                result = pbRandom_preTrace(x)
                log_rng_trace!("pbRandom", x, result, call_site)
                result
            end
        end

        PokeBattle_AI.class_eval do
            alias_method :pbAIRandom_preTrace, :pbAIRandom
            define_method(:pbAIRandom) do |x|
                call_site = caller_locations(1, 20)&.map(&:to_s)&.join(" | ")
                result = pbAIRandom_preTrace(x)
                log_rng_trace!("pbAIRandom", x, result, call_site)
                result
            end
        end

        # Logs into the *same* file/counter as the pbRandom/pbAIRandom draws
        # above (not a separate log) so move-usage entries interleave with
        # RNG draws in true chronological order -- lets us read off exactly
        # which move was executing directly before/after any given draw,
        # rather than having to correlate two logs by timestamp.
        PokeBattle_Battler.class_eval do
            alias_method :pbUseMove_preTrace, :pbUseMove
            define_method(:pbUseMove) do |choice, specialUsage = false|
                moveName = choice[2]&.name || "(nil move)"
                log_rng_trace!("pbUseMove", pbThis, moveName, nil)
                pbUseMove_preTrace(choice, specialUsage)
            end
        end

        # Logs the pre-sort candidate-move array [moveIndex, score, target]
        # that pbChooseMovesTrainer is about to run
        # `choices.sort_by { |choice| -choice[1] }` on -- Array#sort_by isn't
        # guaranteed stable, so if two moves tie on score, which one lands
        # in sortedChoices[0] is implementation/platform-dependent. This
        # dumps move name + score (in the *original*, pre-sort order the
        # moveset was iterated in) so a tie between the two platforms'
        # differing move picks would show up directly as equal scores here.
        PokeBattle_AI.class_eval do
            alias_method :pbChooseMovesTrainer_preTrace, :pbChooseMovesTrainer
            define_method(:pbChooseMovesTrainer) do |idxBattler, choices|
                user = @battle.battlers[idxBattler]
                summary = choices.map { |c| "#{user.getMoves[c[0]]&.name}=#{c[1]}(tgt#{c[2]})" }.join(",")
                log_rng_trace!("aiChoices", user.pbThis, summary, nil)
                pbChooseMovesTrainer_preTrace(idxBattler, choices)
            end
        end
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
            %i[pbEnemyShouldWithdraw? pbGetBestTrainerMoveChoices estimateSwitchScoreCeiling pbScorePredictedPlayerMoves pbGetMoveScore].each do |phase|
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
        install_rng_trace! if ENV["ELO_TEST_RNG_TRACE"]
        if ENV["ELO_TEST_SINGLE_PAIRING"]
            EloTournament.testSinglePairing!
            dump_profile_timing! if ENV["ELO_PROFILE_TIMING"]
        elsif ENV["ELO_TEST_BATCH_PAIRINGS"]
            EloTournament.testBatchPairings!
            dump_profile_timing! if ENV["ELO_PROFILE_TIMING"]
        elsif ENV["ELO_SAVE_REPLAY"]
            EloTournament.saveReplay!
        elsif ENV["ELO_WATCH_REPLAY_NAME"]
            EloTournament.watchReplay!
        elsif ENV["ELO_RUN_BRACKET"]
            EloTournament.runBracket!
        elsif ENV["ELO_DUMP_TRAINER_CARD_DATA"]
            EloTournament.dumpTrainerCardData!
        elsif ENV["ELO_DUMP_CURSE_STRIP_DIFF"]
            EloTournament.dumpCurseStripDiff!
        elsif ENV["ELO_CUSTOM_TRAINER_BATTLES"]
            EloTournament.runCustomTrainerBattles!
        else
            EloTournament.run!
        end
        return nil
    end
end
