; Z-Police level 15: LEVEL15.TXL, the text form of LEVEL15.ZPL
; The source is levels/LEVEL15.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 15
CITY 3
NAME TOKYO
ZOMBIES 30
WAVES 2
FAST 8
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5 BANSHEE 3
WAVE 2 BANSHEE 5 CLUSTERS 4

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
