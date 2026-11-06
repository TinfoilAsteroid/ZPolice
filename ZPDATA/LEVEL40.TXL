; Z-Police level 40: LEVEL40.TXL, the text form of LEVEL40.ZPL
; The source is levels/LEVEL40.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 40
CITY 8
NAME SYDNEY
ZOMBIES 30
WAVES 8
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, CLUSTERS
WAVE 1 GHOST 5 GHOUL 3
WAVE 2 BANSHEE 3
WAVE 3 GHOUL 3
WAVE 4 BANSHEE 3
WAVE 5 GHOUL 3
WAVE 6 BANSHEE 3
WAVE 7 GHOUL 3
WAVE 8 LICH 1 BANSHEE 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
