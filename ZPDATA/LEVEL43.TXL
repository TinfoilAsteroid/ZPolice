; Z-Police level 43: LEVEL43.TXL, the text form of LEVEL43.ZPL
; The source is levels/LEVEL43.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 43
CITY 9
NAME CAIRO
ZOMBIES 40
WAVES 1
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOUL 8

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
