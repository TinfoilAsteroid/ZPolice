; Z-Police level 35: LEVEL35.TXL, the text form of LEVEL35.ZPL
; The source is levels/LEVEL35.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 35
CITY 7
NAME MOSCOW
ZOMBIES 40
WAVES 1
FAST 40
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOUL 8 CLUSTERS 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
