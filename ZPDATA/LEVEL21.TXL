; Z-Police level 21: LEVEL21.TXL, the text form of LEVEL21.ZPL
; The source is levels/LEVEL21.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 21
CITY 5
NAME BERLIN
ZOMBIES 10
WAVES 2
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5
WAVE 2 GHOUL 5 CLUSTERS 4

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
