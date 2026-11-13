; Z-Police level 29: LEVEL29.TXL, the text form of LEVEL29.ZPL
; The source is levels/LEVEL29.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 29
CITY 6
NAME ROME
ZOMBIES 25
WAVES 2
FAST 15
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 BANSHEE 8
WAVE 2 BANSHEE 8

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
