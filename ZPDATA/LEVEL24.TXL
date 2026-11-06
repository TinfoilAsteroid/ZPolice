; Z-Police level 24: LEVEL24.TXL, the text form of LEVEL24.ZPL
; The source is levels/LEVEL24.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 24
CITY 5
NAME BERLIN
ZOMBIES 25
WAVES 5
FAST 12
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, CLUSTERS
WAVE 1 GHOST 5 GHOUL 1
WAVE 2 BANSHEE 2
WAVE 3 GHOUL 1 CLUSTERS 4
WAVE 4 BANSHEE 2
WAVE 5 GHOUL 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
