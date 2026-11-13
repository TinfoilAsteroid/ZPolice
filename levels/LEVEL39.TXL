; Z-Police level 39: LEVEL39.TXL, the text form of LEVEL39.ZPL
; The source is levels/LEVEL39.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 39
CITY 8
NAME SYDNEY
ZOMBIES 30
WAVES 2
FAST 25
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5
WAVE 2 BANSHEE 6 CLUSTERS 4 LICH 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
