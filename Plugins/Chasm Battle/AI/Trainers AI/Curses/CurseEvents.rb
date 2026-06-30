class PokeBattle_Battle
    BattleStartApplyCurse	= HandlerHash2.new
    BattleEndCurse	= HandlerHash2.new
    BattlerEnterCurseEffect	= HandlerHash2.new
    BattlerFaintedCurseEffect	= HandlerHash2.new
    EffectivenessChangeCurseEffect	= HandlerHash2.new
    MoveUsedCurseEffect	= HandlerHash2.new
    BeginningOfTurnCurseEffect	= HandlerHash2.new
    EndOfTurnCurseEffect	= HandlerHash2.new

    # side = which battle side (0 or 1) holds this curse. Threaded through
    # explicitly here because these four triggers act on a side/party
    # directly with no battler argument to disambiguate against -- unlike
    # the battler-context triggers below, there'd be nothing to resolve
    # "which side" against if two different trainers in the battle happen
    # to hold the same curse symbol on opposite sides (this does happen at
    # full-pool scale, e.g. CURSE_PERFECT_LUCK is carried by 7 different
    # trainers).
    def triggerBattleStartApplyCurse(curse_policy, side, battle, curses_array)
        ret = BattleStartApplyCurse.trigger(curse_policy, side, battle, curses_array)
        return ret || curses_array
    end

    def triggerBattleEndCurse(curse_policy, side, battle)
        BattleEndCurse.trigger(curse_policy, side, battle)
    end

    def triggerBattlerEnterCurseEffect(curse_policy, battler, battle)
        ret = BattlerEnterCurseEffect.trigger(curse_policy, battler, battle)
        return ret || false
    end

    def triggerBattlerFaintedCurseEffect(curse_policy, battler, battle)
        ret = BattlerFaintedCurseEffect.trigger(curse_policy, battler, battle)
        return ret || false
    end

    def triggerEffectivenessChangeCurseEffect(curse_policy, moveType, user, target, effectiveness)
        ret = EffectivenessChangeCurseEffect.trigger(curse_policy, moveType, user, target, effectiveness)
        return ret || effectiveness
    end

    def triggerBeginningOfTurnCurseEffect(curse_policy, side, battle)
        BeginningOfTurnCurseEffect.trigger(curse_policy, side, battle)
    end

    def triggerEndOfTurnCurseEffect(curse_policy, side, battle)
        EndOfTurnCurseEffect.trigger(curse_policy, side, battle)
    end

    def triggerMoveUsedCurseEffect(curse_policy, user, target, move)
        ret = MoveUsedCurseEffect.trigger(curse_policy, user, target, move)
        return ret || true
    end

    def hideDataboxes
        numFrames = (Graphics.frame_rate*0.4).floor
        alphaDiff = (255.0/numFrames).ceil
        for j in 0..numFrames
            opacity = (numFrames - j) * alphaDiff
            databoxes.each do |dataBox|
                next if dataBox.disposed?
                dataBox.opacity = opacity
                dataBox.update
            end
            yield opacity if block_given?
            Graphics.update
        end
    end

    def returnDataboxes
        numFrames = (Graphics.frame_rate*0.4).floor
        alphaDiff = (255.0/numFrames).ceil
        for j in 0..numFrames
            opacity = j * alphaDiff
            databoxes.each do |dataBox|
                next if dataBox.disposed?
                dataBox.opacity = opacity
                dataBox.update
            end
            yield opacity if block_given?
            Graphics.update
        end
    end

    def databoxes
        boxes = []
        eachBattler do |b|
            databox = scene.sprites["dataBox_#{b.index}"]
            boxes.push(databox)
        end
        return boxes
    end

    def amuletActivates(curseName, explanation = nil, noAmulet = false)
        echoln("Amulet actives!")
        announceText = _INTL("\\i[TAROTAMULET_ACTIVE]The Tarot Amulet glows with power!")
        if noAmulet
            announceText = _INTL("The trainer exudes an overwhelming negative energy!")
        end
        pbDisplaySlower(announceText)

        curseBG = scene.pbAddSprite("curseBG",0,0,"Graphics/Pictures/Battle/cursebg",@viewport)
        curseBG.visible = true
        curseBG.z = 100_000

        hideDataboxes { |opacity|
            curseBG.opacity = (255 - opacity) / 2
        }

        # Show the curse name in a big bold way
        pbSEPlay("Anim/PRSFX- Spectral Thief2", 300, 20)
        pbSEPlay("Anim/PRSFX- Telekinesis", 100, 120)

        msgwindow = pbCreateMessageWindow
        msgwindow.z = 100_001
        waitTime = amuletMessageDuration
        fontSize = 48
        msgwindow.lineHeight(48)
        curseName = _INTL("\\ts[]<c3=4C0D0D,FFFFFF22><b><outln2><ac><fs={1}>\\w[]\\wu\\l[12]{2}</fs></ac></outln2></b></c3>\\wt[{3}]",fontSize,curseName,waitTime)
        curseName = "<fn=Didact Gothic>" + curseName + "</fn>"
        pbMessageDisplay(msgwindow,curseName)

        pbDisplaySlower(explanation) if explanation
        pbDisposeMessageWindow(msgwindow)
        Input.update

        returnDataboxes { |opacity|
            curseBG.opacity = (255 - opacity) / 2
        }
        curseBG.visible = false
    end
end

def amuletMessageDuration
    dur = 70
    dur -= 8 * $Options.textspeed
    return dur
end

class PokeBattle_Battler
    # @curses holds [policy, side] tuples (side = 0 or 1, whichever battle
    # side holds that curse) rather than bare symbols, specifically so this
    # stays correct when two different trainers in the same battle hold an
    # identical curse symbol on opposite sides -- confirmed to actually
    # happen at full-pool scale (e.g. CURSE_PERFECT_LUCK is carried by 7
    # different trainers). Scanning per-battler like this resolves each
    # side independently instead of relying on a single global lookup that
    # a duplicate symbol could clobber.
    def curseHolder?(curseID)
        @battle.curses.any? { |policy, side| policy == curseID && side == idxOwnSide }
    end

    def curseVictim?(curseID)
        @battle.curses.any? { |policy, side| policy == curseID && side == idxOpposingSide }
    end
end
