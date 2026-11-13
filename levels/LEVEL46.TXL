; Z-Police level 46: LEVEL46.TXL, the text form of LEVEL46.ZPL
; The source is levels/LEVEL46.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 46
CITY 10
NAME CHICAGO
ZOMBIES 20
WAVES 1
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 LICH 8 CLUSTERS 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
