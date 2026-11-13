; Z-Police level 18: LEVEL18.TXL, the text form of LEVEL18.ZPL
; The source is levels/LEVEL18.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 18
CITY 4
NAME NEW YORK
ZOMBIES 20
WAVES 2
FAST 9
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 8 CLUSTERS 2
WAVE 2 CLUSTERS 2 BANSHEE 8

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
