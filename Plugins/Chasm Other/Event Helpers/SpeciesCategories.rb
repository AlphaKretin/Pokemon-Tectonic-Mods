
def isCat?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Cat")
end

def isAlien?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Alien")
end

def isBat?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Bat")
end

def isSmart?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Smart")
end

def isKnight?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Knight")
end

def isFrog?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Frog")
end

def isBandMember?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("BandMember")
end

def isTurtle?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Turtle")
end

def isTMNT?(species)
	return true if isTurtle?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("TMNT")
end

def isKing?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("King")
end

def isQueen?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Queen")
end

def isSmasher?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Smasher")
end

def isPirateCrew?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("PirateCrew")
end

def isMushroom?(species)
	speciesData = GameData::Species.get(species)
	return speciesData.flags.include?("Mushroom")
end