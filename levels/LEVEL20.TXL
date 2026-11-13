; Z-Police level 20: LEVEL20.TXL, the text form of LEVEL20.ZPL
; The source is levels/LEVEL20.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 20
CITY 4
NAME NEW YORK
ZOMBIES 40
WAVES 1
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 BANSHEE 8 CLUSTERS 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
