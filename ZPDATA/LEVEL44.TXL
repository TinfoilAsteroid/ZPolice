; Z-Police level 44: LEVEL44.TXL, the text form of LEVEL44.ZPL
; The source is levels/LEVEL44.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 44
CITY 9
NAME CAIRO
ZOMBIES 40
WAVES 1
FAST 22
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 BANSHEE 2 GHOST 2 GHOUL 2 LICH 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
