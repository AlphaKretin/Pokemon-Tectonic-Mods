CASABA_VILLA_WAYPOINT_NAME = "Villa Grass"
BLUEPOINT_GROTTO_WAYPOINT_NAME = "Bluepoint Grotto"
CASABA_VILLA_MAP_ID = 136
CASABA_VILLA_WAYPOINT_EVENT_ID = 52

def playTotemTutorialIfNeeded(totemEventID)
    if !isWaypointUnlocked?(BLUEPOINT_GROTTO_WAYPOINT_NAME) || !isWaypointUnlocked?(CASABA_VILLA_WAYPOINT_NAME)
        playTotemTutorial(totemEventID)
    end
end

def playTotemTutorial(totemEventID)
    playingBGM = $game_system.getPlayingBGM
    $game_system.bgm_pause(1.0)

    pbWait(20)

    showExclamation(-1)

    pbWait(20)

    pbMessage(_INTL("\\i[SPANNINGBAND]What? The Spanning Bands are suddenly glowing!"))

    slideCameraToEvent(totemEventID)

    pbMessage(_INTL("\\i[SPANNINGBAND]They glow in sync with the <imp>Avatar Totem</imp>."))

    pbMessage(_INTL("\\i[SPANNINGBAND]A vision of Casaba Villa flashes across your mind."))

    pbMessage(_INTL("\\i[SPANNINGBAND]You sense that some sort of <imp>connection</imp> has been made."))

    $waypoints_tracker.addWaypoint(BLUEPOINT_GROTTO_WAYPOINT_NAME,get_event(totemEventID))

    setWaypoint(CASABA_VILLA_WAYPOINT_NAME,CASABA_VILLA_MAP_ID,CASABA_VILLA_WAYPOINT_EVENT_ID)

    slideCameraToPlayer

    $game_system.bgm_resume(playingBGM)
end