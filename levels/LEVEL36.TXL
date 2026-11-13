; Z-Police level 36: LEVEL36.TXL, the text form of LEVEL36.ZPL
; The source is levels/LEVEL36.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 36
CITY 8
NAME SYDNEY
ZOMBIES 20
WAVES 2
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5 GHOUL 2 LICH 1
WAVE 2 GHOUL 2 GHOST 3 LICH 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
