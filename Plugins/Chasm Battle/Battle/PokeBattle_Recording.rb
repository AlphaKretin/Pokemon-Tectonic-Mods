# Generic monkeypatch making Array#sample deterministic/replayable for any
# battle whose pbRandom is authoritative (recorded/replayed battles below;
# also used by Cable Club multiplayer battles -- see
# Plugins/Chasm Cable Club/[001] Cable Club Client/003_Battle_CableClub.rb,
# which requires this plugin and so loads after it). Array#sample draws
# from Ruby's own global RNG, invisible to pbRandom's record/replay
# interception below -- a multi-hit move's hit count
# (Move_Codes_Multihit.rb's hitChances.sample) rolled this way during
# recording is never logged into @random, and during replay rolls an
# independent, unsynced value instead of replaying the recorded one,
# instantly diverging record vs replay for the rest of the battle. Routing
# Array#sample itself through whichever battle is current fixes every call
# site at once (Metronome, Assist, Sleep Talk, item-eating abilities, ...),
# not just multi-hit moves.
module DeterministicSample
	def self.included(base)
		base.prepend(InstanceMethods)
	end

	module InstanceMethods
		def initialize(*args)
			super
			DeterministicSample.override_array_sample
		end
	end

	def self.override_array_sample
		return if Array.method_defined?(:original_ruby_sample)
		Array.class_eval do
			alias_method :original_ruby_sample, :sample

			define_method :sample do |n = nil, random: nil|
				battle = Thread.current[:current_pbrandom_battle]
				return original_ruby_sample(n, random: random) unless battle&.respond_to?(:pbRandom)
				if n.nil?
					return nil if empty?
					self[battle.pbRandom(length)]
				else
					return [] if n <= 0 || empty?
					n = [n, length].min
					result = []
					each_with_index do |item, index|
						if index < n
							result << item
						else
							j = battle.pbRandom(index + 1)
							result[j] = item if j < n
						end
					end
					result
				end
			end
		end
	end
end

module PokeBattle_BattleRecorder

	attr_accessor :type #Battle type. 0 for wild, 1 for trainer, 2 for avatar

	attr_accessor :recorded_choices #Array of the move choices made
	attr_accessor :recorded_switches #Array of switches made
	attr_accessor :random #Array of the random numbers used in the battle

	attr_accessor :player_info
	attr_accessor :player_party
	attr_accessor :player_party_starts
	
	attr_accessor :opponent_info
	attr_accessor :opponent_party
	attr_accessor :opponent_party_starts

	attr_accessor :starting_weather
	attr_accessor :starting_weather_duration

	attr_accessor :held_items

	attr_accessor :save_battle
	attr_accessor :battle_rules

	def initialize(scene, playerParty, foeParty, playerTrainers, foeTrainers, type)
		DeterministicSample.override_array_sample
		Thread.current[:current_pbrandom_battle] = self
		super(scene, playerParty, foeParty, playerTrainers, foeTrainers)
		@recorded_choices = []
		@recorded_switches = []
		@random = []
		@diag_logs = Hash.new { |h, k| h[k] = [] }
		@is_recorded = true
		@save_battle = true
		@type = type
	end

	# Generic diagnostic-log channel system, shared by every "trace what
	# happened, turn by turn" log this recorder/replayer pair produces
	# (random draws, priority-tiebreak order, boss AI decisions, ...) --
	# previously each of these was its own copy-pasted @foo_log array +
	# saveFooLog method. A channel name maps to one file,
	# ./Analysis/<channel>_record.txt here (buffered, one write at
	# pbEndOfBattle -- recording is stable, a battle that fails here is just
	# a failed generation attempt, already reported by replay.rb's own
	# rescue). See PokeBattle_BattleReplayer#diagLog for the replay-side
	# override, which needs to flush per-call instead since that's exactly
	# the case where the battle is most likely to crash or need killing
	# partway through.
	def diagLog(channel, line)
		@diag_logs[channel].push("#{line}#{$/}")
	end

	def saveDiagLogs
		suffix = @save_battle ? "record" : "replay"
		@diag_logs.each_key { |channel| saveDiagLog(channel, "#{channel}_#{suffix}.txt") }
	end

	def saveDiagLog(channel, path)
		File.open("./Analysis/" + path, "wb") { |f| f.write(@diag_logs[channel].join("")) }
	end

	def self.createDir
		Dir.mkdir("./VSRecorder") unless Dir.exists?("./VSRecorder")
		if $current_save_file_name.nil?
			return
		end
		save_file_name = $current_save_file_name.split("/")[1].delete_suffix(".rxdata")
		Dir.mkdir("./VSRecorder/#{save_file_name}") unless Dir.exists?("./VSRecorder/#{save_file_name}")
	end

	def pbRandom(x)
		if x == 1 && x.is_a?(Integer) then
			return 0 # Don't add to random stack if the outcome is certain
		end
		ret = rand(x)
		@random.push(ret)
		diagLog("random", "#{ret.to_s}#{$/}#{caller.to_s}")
		return ret
	end

	def recordChoices
		@choices.each_with_index do |c, i|
			c_clone = c.clone
			c_clone[2] = nil unless c_clone.nil? #Remove move object (not parsable)
			@recorded_choices[@turnCount][i].push(c_clone)
		end
	end

	def pbCommandPhase
		@recorded_choices.push([]) #Add turn array
    (maxBattlerIndex + 1).times { |i| @recorded_choices[@turnCount].push([])} #Add array for each battler
		super
		recordChoices
  end

	def pbExtraCommandPhase
		super
		recordChoices
	end

	def recordSkippedTurn
		@recorded_choices.push([])
	end

	def pbStartBattle
		# @party1/@party2 aren't dumped separately: they share the exact same
		# Pokemon objects as @player[i].party/@opponent[i].party by reference
		# (pbTrainerBattleCore builds the combined array by pushing each
		# trainer's own party members, not cloning them), which is how a
		# Pokemon fainting mid-battle is visible through both the trainer
		# wrapper (Trainer#alive_pokemon_count, used by e.g. isLastAlive? for
		# ARCANEFINALE) and the battle's own party array. Marshal.dump(@player)/
		# Marshal.dump(@opponent) already recursively serializes each
		# trainer's .party along with it, so a separate dump of @party1/
		# @party2 would be redundant data -- and worse, loading it back via a
		# second, independent Marshal.load would produce a second, separate
		# object graph, breaking that reference sharing (confirmed: replay's
		# @opponent[i].party stayed frozen at full HP while @party2 -- what
		# battlers actually mutate -- updated normally, so isLastAlive?'s
		# alive_pokemon_count read the wrong copy). See PokeBattle_BattleReplayer#initialize.
		@player_info                  = Marshal.dump(@player)
		@opponent_info                = Marshal.dump(@opponent)
		@player_party_starts          = Marshal.dump(@party1starts)
		@opponent_party_starts        = Marshal.dump(@party2starts)
		@starting_weather             = @field.weather
		@starting_weather_duration    = @field.weatherDuration
		@held_items                   = Marshal.dump(@items)
		super
	end

	def pbEndOfBattle
		saveBattle("Last battle") if @save_battle
		saveDiagLogs
		Thread.current[:current_pbrandom_battle] = nil
		super
	end

	# Always records the switch-in decision now, not just the player's own
	# (previously only reached via pbPartyScreen). An AI-decided forced
	# switch-in (U-turn, Parting Shot, a fainted Pokemon, etc.) re-invoked
	# @battleAI.pbDefaultChooseNewEnemy on replay too, relying on it
	# rederiving the exact same choice -- but that scoring depends on the
	# AI's guessed/predicted knowledge of the opponent's moves
	# (highestMoveScoreForBattler -> pbScorePredictedPlayerMoves in
	# AI_Switch.rb), which comes from whatever heuristic populated
	# @moveGuessHeuristics/@benchmarkMode at record time (e.g. the
	# tournament's HEURISTIC_BASELINE "peek at real STAB moves" heuristic).
	# Neither of those is saved into the recording or restored by
	# PokeBattle_BattleReplayer, so replay's guessed moveset can differ from
	# record's, re-deriving a *different* switch-in choice for the exact
	# same board state -- confirmed diverging on a real replay (an
	# AI-recorded Parting Shot switch-in came back as a different Pokemon
	# on watch). Recording every switch-in verbatim, the same way a
	# player's own choice already was, closes this off entirely rather than
	# needing record-time AI state to be reconstructed bit-for-bit.
	def pbSwitchInBetween(idxBattler, checkLaxOnly: false, canCancel: false, safeSwitch: nil)
		ret = if pbOwnedByPlayer?(idxBattler) && !@autoTesting && !@controlPlayer
			pbPartyScreen(idxBattler, checkLaxOnly, canCancel)
		else
			@battleAI.pbDefaultChooseNewEnemy(idxBattler, safeSwitch)
		end
		@recorded_switches.push(ret)
		ret
	end

	def registerRecordedChoice(index)
    	return if @recorded_choices[@turnCount][index].length < @commandPhasesThisRound
    	@recorded_choices[@turnCount][index][@commandPhasesThisRound-1] ||= []
    	@recorded_choices[@turnCount][index][@commandPhasesThisRound-1].push(@recorded_choice)
	end

	def registerRules
		@battle_rules = $PokemonTemp.battleRules.clone
		@battle_rules["canLose"] = @canLose
		@battle_rules["canRun"] = @canRun
		@battle_rules["noexp"] = true if !@expGain
		@battle_rules["nomoney"] = true if !@moneyGain
		@battle_rules["turnstosurvive"] = @turnsToSurvive
		@battle_rules["anims"] = true if @showAnims
		@battle_rules["noanims"] = true if !@showAnims
		@battle_rules["weather"] = @defaultWeather
		@battle_rules["environment"] = @environment
		@battle_rules["backdrop"] = @backdrop
		@battle_rules["base"] = @backdropBase
		@battle_rules["playerambush"] = @playerAmbushing
		@battle_rules["foeambush"] = @foeAmbushing
		@battle_rules["lanetargeting"] = @laneTargeting
		@battle_rules["doubleshift"] = @doubleShift
	end

	def getBattleData
		return Marshal.dump({
			:type => @type,
			:recorded_choices => @recorded_choices,
			:recorded_switches => @recorded_switches,
			:random => @random,
			:player_info => @player_info,
			:player_party_starts => @player_party_starts,
			:opponent_info => @opponent_info,
			:opponent_party_starts => @opponent_party_starts,
			:starting_weather => @starting_weather,
			:starting_weather_duration => @starting_weather_duration,
			:held_items => @held_items,
			:rules => Marshal.dump(@battle_rules),
			:endSpeeches => (@endSpeeches) ? @endSpeeches.clone : "",
			:endSpeechesWin => (@endSpeechesWin) ? @endSpeechesWin.clone : "",
			:canRun => @canRun,
			:switchStyle => @switchStyle,
			:showAnims => @showAnims,
			:backdrop => @backdrop,
			:backdropBase => @backdropBase,
			:time => @time,
			:environment => @environment,
			:level_cap => getLevelCap,
			:version => Settings::GAME_VERSION
		})
	end

	def saveBattle(name)
		return if $current_save_file_name.nil?
		save_file_name = $current_save_file_name.split("/")[1].delete_suffix(".rxdata")
		PokeBattle_BattleRecorder.createDir
		File.open("./VSRecorder/#{save_file_name}/#{name}.dat", "wb") { |f| f.write(getBattleData) }
	end

	# Ground truth for comparing a recorded battle's turn order (including
	# speed-tie resolution) against the same battle's replay -- see the call
	# in Battle_Action_AttacksPriority.rb's pbCalculatePriority.
	def logPriorityOrder(line)
		diagLog("priority", line)
	end
end

module PokeBattle_BattleReplayer
	include PokeBattle_BattleRecorder

	attr_accessor :randomindex
	attr_accessor :level_cap

	def initialize(scene, file_name)
		raise _INTL("Record cannot be opened, as no save has been made.") if $current_save_file_name.nil?
		save_file_name = $current_save_file_name.split("/")[1].delete_suffix(".rxdata")
		raise _INTL("Record {1} does not exist", file_name) unless File.exists?("./VSRecorder/#{save_file_name}/#{file_name}.dat")
		battle = File.open("./VSRecorder/#{save_file_name}/#{file_name}.dat", "rb") {|f| Marshal.load(f)}
		raise LoadError _INTL("Record is from a different version ({1}), and cannot be opened.", battle[:version]) if Settings::GAME_VERSION != battle[:version]
		
		@randomindex               = 0
		@player_info               = Marshal.load(battle[:player_info])
		@opponent_info             = Marshal.load(battle[:opponent_info])
		# Not loaded from a separate dump: rebuilt by concatenating each
		# loaded trainer's own .party, the same way pbTrainerBattleCore
		# builds the combined party in the first place (TrainerBattles.rb).
		# This keeps @party1/@party2 sharing the exact same Pokemon objects
		# as @player_info[i].party/@opponent_info[i].party by reference --
		# see the comment on pbStartBattle above for why that matters (a
		# separate Marshal round-trip of the same data breaks that sharing,
		# which is what let isLastAlive?'s alive_pokemon_count silently read
		# a frozen, always-full-HP copy of the party during replay).
		@player_party              = @player_info.flat_map(&:party)
		@opponent_party            = @opponent_info.flat_map(&:party)


		echo_rules_debug = false
		arg_rules = ["terrain", "weather", "environment", "environ", "backdrop", "battleback", "base", "outcome", "outcomevar", "turnstosurvive"]
		echoln("=====REPLAY RULES BEGIN=====") if echo_rules_debug
		Marshal.load(battle[:rules]).each_pair { |rule, val| 
			echoln("RULE : " + rule.to_s + " - " + val.to_s) if echo_rules_debug
			if arg_rules.include?(rule)
				setBattleRule(rule, val)
			elsif rule == "size"
				setBattleRule(val)
			else 
				setBattleRule(rule)
			end
		}
		echoln("=====REPLAY RULES END=====") if echo_rules_debug
		
		super(scene, @player_party, @opponent_party, @player_info, @opponent_info, battle[:type])
		
		@player_party_starts       = Marshal.load(battle[:player_party_starts])
		@opponent_party_starts     = Marshal.load(battle[:opponent_party_starts])
		@held_items                = Marshal.load(battle[:held_items])
		@starting_weather          = battle[:starting_weather]
		@starting_weather_duration = battle[:starting_weather_duration]
		@endSpeeches               = battle[:endSpeeches]
		@endSpeechesWin            = battle[:endSpeechesWin]
		@canRun                    = battle[:canRun]
		@switchStyle               = battle[:switchStyle]
		@showAnims                 = battle[:showAnims]
		@level_cap                 = battle[:level_cap]
		@recorded_choices          = battle[:recorded_choices]
		@recorded_switches         = battle[:recorded_switches]
		@random                    = battle[:random]
		@save_battle               = false
		@is_replayed               = true
		@is_recorded               = false
		@backdrop                  = battle[:backdrop]
		@backdropBase              = battle[:backdropBase]
		@time                      = battle[:time]
		@environment               = battle[:environment]
		@expGain                   = false
		
		@party1starts              = @player_party_starts
		@party2starts              = @opponent_party_starts
		@field.weather             = @starting_weather
		@field.weatherDuration     = @starting_weather_duration
		@items                     = @held_items
		
		@bossBattle = true if battle[:type] == 2

		# Diagnostic-log channels (random/priority/boss_ai/...) exist
		# specifically to diagnose a desyncing replay -- exactly the case
		# where the battle is most likely to crash or need killing partway
		# through. Recording doesn't have this problem (a battle that fails
		# there is just a failed generation attempt, already reported by
		# replay.rb's own rescue), so it's left buffered and written once
		# from pbEndOfBattle same as before (see
		# PokeBattle_BattleRecorder#diagLog). Replay instead appends+flushes
		# per diagLog call below (see the saveDiagLogs no-op further down,
		# which would otherwise clobber this with an empty write on a battle
		# that *does* reach a clean end) -- @diag_truncated starts empty here
		# so the first diagLog call for each channel truncates fresh instead
		# of appending to a stale file from a previous watch.
		@diag_truncated = {}

	end

	def pbRandom(x)
		if x == 1 && x.is_a?(Integer) then
			return 0 # Don't take from random stack if the outcome is certain
		end
		ret = @random[@randomindex]
		@randomindex += 1
		# caller must be captured here, not inside diagLog's File.open block --
		# evaluating it in there reports PokeBattle_Recording.rb's own `open`
		# frame as the top of the stack instead of whatever actually called
		# pbRandom, making every single draw look like a false divergence.
		call_stack = caller.to_s
		diagLog("random", "#{ret.to_s}#{$/}#{call_stack}")
		return ret
	end

	# Overrides PokeBattle_BattleRecorder#diagLog -- replay needs to hit disk
	# immediately per call instead of buffering for a single end-of-battle
	# write, since replay is exactly the case that might crash or get killed
	# mid-battle. Each channel's file is truncated on its first write this
	# run (instead of upfront, since channel names aren't known ahead of
	# time), then appended to for the rest of the run.
	def diagLog(channel, line)
		path = "./Analysis/#{channel}_replay.txt"
		mode = @diag_truncated[channel] ? "a" : "w"
		@diag_truncated[channel] = true
		File.open(path, mode) { |f| f.write("#{line}#{$/}") }
	end

	# No-op: every channel is already fully written by the per-call appends
	# in diagLog above by the time pbEndOfBattle would call this -- letting
	# PokeBattle_BattleRecorder's version run here too would overwrite that
	# with whatever's left in the (now-unused) @diag_logs buffers, which is
	# empty.
	def saveDiagLogs; end

	def pbCommandPhase
		pbCommandPhaseLoop(false)
		@choices = []
		@recorded_choices[@turnCount].each do |c|
			if c.length == 0 # If choice is empty
				@choices.push([])
				next
			end
			@choices.push(c[0])
			next if @choices[-1].nil?
			currentBattlerIndex = @choices.length - 1
			if @choices[-1][0] == :UseMove
				if @choices[-1][1] == -1
					@choices[-1][2] = @struggle
				else
					@choices[-1][2] = @battlers[currentBattlerIndex].moves[@choices[-1][1]] #Restore move from index
				end
			elsif @choices[-1][0] == :None && !@battlers[currentBattlerIndex].fainted? #If no action was taken and the battler is able (run/forfeit)
				pbRun(currentBattlerIndex)
			end
		end
  end

	def pbExtraCommandPhase
		pbCommandPhaseLoop(false)
		@choices = []
		@recorded_choices[@turnCount].each do |c|
			if c.length < @commandPhasesThisRound + 1 # If there is no choice for this command phase
				@choices.push([])
				next
			end
			@choices.push(c[@commandPhasesThisRound]) # Not decremented since commandPhasesThisRound is incremented AFTER the command phase
			next if @choices[-1].nil?
			currentBattlerIndex = @choices.length - 1
			if @choices[-1][0] == :UseMove
				if @choices[-1][1] == -1
					@choices[-1][2] = @struggle
				else
					@choices[-1][2] = @battlers[currentBattlerIndex].moves[@choices[-1][1]] #Restore move from index
				end
			end
		end
	end

	def registerReplayedChoice(index)
		choice = @recorded_choices[@turnCount][index]
		if choice.nil?
			@replayed_choice = nil
		elsif choice.length < 5
			@replayed_choice = @recorded_choices[@turnCount][index][4]
		else
			@replayed_choice = nil
		end
	end

	# Every switch-in decision is recorded now (see the recorder-side
	# pbSwitchInBetween above), so replay always plays back the recorded
	# choice verbatim instead of re-deriving an AI-owned switch-in fresh --
	# closing off the record/replay AI-knowledge divergence that let a
	# recorded and watched battle disagree on which Pokemon came in.
	def pbSwitchInBetween(idxBattler, checkLaxOnly: false, canCancel: false, safeSwitch: nil)
		@recorded_switches.shift
	end

end

class PokeBattle_Battle
	def registerRecordedChoice(index); end
	def registerReplayedChoice(index); end
	def registerRules; end
	def recordSkippedTurn; end
	def logPriorityOrder(line); end
	def diagLog(channel, line); end
end

class PokeBattle_TectonicRecordedBattle < PokeBattle_Battle
	include PokeBattle_BattleRecorder
end

class PokeBattle_TectonicReplayedBattle < PokeBattle_Battle
	include PokeBattle_BattleReplayer
end

def playRecordedBattle(record_name, force_show_anims: nil, action_log_path: nil)
	original_level_cap = getLevelCap
	scene = pbNewBattleScene
	# Every recorded battle is already-decided, non-interactive playback --
	# same flag Battle Frontier Challenge battles use (attr comment: "For
	# non-interactive battles, can quit immediately"). Makes a message's own
	# page-break pause resolve the same way MESSAGE_PAUSE_TIME's timer
	# already does for a single-page message, rather than genuinely
	# blocking for a keypress, and lets BACK quit out of watching early --
	# both apply equally whether watching via the in-game VS Recorder item
	# or the viewer's Watch tab.
	scene.abortable = true
	begin
		battle = PokeBattle_TectonicReplayedBattle.new(scene, record_name)
	rescue LoadError => e
		pbMessage(_INTL("This record cannot be opened ({1}).", e.message))
		return
	end

	# Ground-truth-vs-playback diff tool: same human-readable per-turn
	# description as AI_Benchmark.rb's recording-side action log (also
	# built off describeAction against this exact [type, ...] choice
	# shape), but on the replay side instead -- @choices here is rebuilt
	# from @recorded_choices each phase (see pbCommandPhase/
	# pbExtraCommandPhase above), so this reflects what the replay is
	# actually about to execute this turn. Written turn-by-turn (append +
	# close, not buffered to a single write at the end) so a desync that
	# crashes or has to be killed mid-battle still leaves a partial log to
	# diff against replay_action_log.txt up to wherever it stopped.
	if action_log_path
		File.open(action_log_path, "w") { |f| } # start each watch from a clean file
		battle.define_singleton_method(:logReplayedChoices) do
			lines = []
			@choices.each_with_index do |c, i|
				b = @battlers[i]
				next unless b && c && !c.empty?
				description = describeAction(b, c) || c[0].to_s
				lines << "Turn #{@turnCount + 1}, #{b.pbThis(true)}: #{description}"
			end
			File.open(action_log_path, "a") { |f| f.puts(lines) } unless lines.empty?
		end
		battle.define_singleton_method(:pbCommandPhase) do
			super()
			logReplayedChoices
		end
		battle.define_singleton_method(:pbExtraCommandPhase) do
			super()
			logReplayedChoices
		end
	end

	pbPrepareBattle(battle)
	# AI-vs-AI recordings always carry showAnims=false (AI_Benchmark.rb sets
	# it for simulation speed), which pbPrepareBattle's rules-replay then
	# treats as a "noanims" battle rule baked into the recording -- clobbering
	# whatever the $Options.battlescene-based default would have been
	# (Overworld_BattleStarting.rb:83-84). force_show_anims lets a caller
	# (e.g. the viewer's watch.rb) override that baked-in value explicitly,
	# same true/false the battlescene option would otherwise have produced.
	battle.showAnims = force_show_anims unless force_show_anims.nil?
	battle.registerRules
  $PokemonTemp.clearBattleRules

	setLevelCap(battle.level_cap, false)

	decision = 0	
	case battle.type
	when 0 #Wild battle
		pbBattleAnimation(pbGetWildBattleBGM(battle.party2),(battle.party2.length==1) ? 0 : 2,battle.party2) do
			pbSceneStandby do
				decision = battle.pbStartBattle
			end
		end
		Input.update
	when 1 #Trainer battle
		pbBattleAnimation(pbGetTrainerBattleBGM(battle.opponent), battle.singleBattle? ? 1 : 3, battle.opponent) do
			pbSceneStandby do
				decision = battle.pbStartBattle
			end
		end
		Input.update
	when 2 #Avatar battle
		pbBattleAnimation(pbGetAvatarBattleBGM(battle.party2), (battle.party2.length == 1) ? 0 : 2, battle.party2) do
			pbSceneStandby do
				decision = battle.pbStartBattle
			end
		end
		Input.update
	else
		raise _INTL("Recorded battle has an invalid battle type. ({1})", battle.type)
	end

	setLevelCap(original_level_cap, false)
	decision
end