; Z-Police level 19: LEVEL19.TXL, the text form of LEVEL19.ZPL
; The source is levels/LEVEL19.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 19
CITY 4
NAME NEW YORK
ZOMBIES 25
WAVES 1
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 4 BANSHEE 4

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
