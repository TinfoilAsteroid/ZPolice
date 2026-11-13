; Z-Police level 32: LEVEL32.TXL, the text form of LEVEL32.ZPL
; The source is levels/LEVEL32.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 32
CITY 7
NAME MOSCOW
ZOMBIES 15
WAVES 2
FAST 15
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOUL 2 GHOST 2 BANSHEE 2
WAVE 2 GHOUL 5 BANSHEE 1 GHOST 1 LICH 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
