; Z-Police level 33: LEVEL33.TXL, the text form of LEVEL33.ZPL
; The source is levels/LEVEL33.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 33
CITY 7
NAME MOSCOW
ZOMBIES 20
WAVES 2
FAST 17
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 1 GHOUL 3 CLUSTERS 4
WAVE 2 BANSHEE 3 CLUSTERS 4 GHOUL 2 LICH 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
