; Z-Police level 5: LEVEL05.TXL, the text form of LEVEL05.ZPL
; The source is levels/LEVEL05.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 5
CITY 1
NAME LONDON
ZOMBIES 30
WAVES 1
FAST 3
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, CLUSTERS
WAVE 1 LICH 1 GHOST 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
