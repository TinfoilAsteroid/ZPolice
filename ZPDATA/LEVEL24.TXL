; Z-Police level 24: LEVEL24.TXL, the text form of LEVEL24.ZPL
; The source is levels/LEVEL24.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 24
CITY 5
NAME BERLIN
ZOMBIES 30
WAVES 2
FAST 12
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 5 GHOUL 1 BANSHEE 1
WAVE 2 GHOUL 4 CLUSTERS 2 BANSHEE 2 GHOST 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
