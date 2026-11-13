; Z-Police level 45: LEVEL45.TXL, the text form of LEVEL45.ZPL
; The source is levels/LEVEL45.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 45
CITY 9
NAME CAIRO
ZOMBIES 40
WAVES 2
FAST 25
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 BANSHEE 2 GHOUL 2 LICH 2 GHOST 2
WAVE 2 CLUSTERS 3 LICH 4 GHOUL 4

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
