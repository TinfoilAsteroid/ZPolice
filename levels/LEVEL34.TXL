; Z-Police level 34: LEVEL34.TXL, the text form of LEVEL34.ZPL
; The source is levels/LEVEL34.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 34
CITY 7
NAME MOSCOW
ZOMBIES 25
WAVES 7
FAST 17
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, CLUSTERS
WAVE 1 GHOST 5 GHOUL 2
WAVE 2 BANSHEE 3
WAVE 3 GHOUL 2
WAVE 4 BANSHEE 3
WAVE 5 GHOUL 2
WAVE 6 BANSHEE 3
WAVE 7 GHOUL 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
