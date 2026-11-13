; Z-Police level 47: LEVEL47.TXL, the text form of LEVEL47.ZPL
; The source is levels/LEVEL47.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 47
CITY 10
NAME CHICAGO
ZOMBIES 25
WAVES 1
FAST 25
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOUL 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
