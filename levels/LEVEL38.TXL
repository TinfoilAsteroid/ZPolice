; Z-Police level 38: LEVEL38.TXL, the text form of LEVEL38.ZPL
; The source is levels/LEVEL38.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 38
CITY 8
NAME SYDNEY
ZOMBIES 25
WAVES 2
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5 GHOUL 2
WAVE 2 BANSHEE 3 LICH 2 GHOUL 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
