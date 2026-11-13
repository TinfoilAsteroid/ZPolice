; Z-Police level 48: LEVEL48.TXL, the text form of LEVEL48.ZPL
; The source is levels/LEVEL48.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 48
CITY 10
NAME CHICAGO
ZOMBIES 40
WAVES 4
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 CLUSTERS 4
WAVE 2 CLUSTERS 3
WAVE 3 CLUSTERS 2
WAVE 4 CLUSTERS 1 LICH 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
