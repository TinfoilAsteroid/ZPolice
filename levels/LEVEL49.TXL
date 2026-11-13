; Z-Police level 49: LEVEL49.TXL, the text form of LEVEL49.ZPL
; The source is levels/LEVEL49.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 49
CITY 10
NAME CHICAGO
ZOMBIES 40
WAVES 3
FAST 40
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 CLUSTERS 6
WAVE 2 BANSHEE 3 CLUSTERS 5
WAVE 3 LICH 8 CLUSTERS 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
