; Z-Police level 26: LEVEL26.TXL, the text form of LEVEL26.ZPL
; The source is levels/LEVEL26.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 26
CITY 6
NAME ROME
ZOMBIES 10
WAVES 6
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, CLUSTERS
WAVE 1 GHOST 5 GHOUL 1
WAVE 2 BANSHEE 2
WAVE 3 GHOUL 1
WAVE 4 BANSHEE 2
WAVE 5 GHOUL 1
WAVE 6 BANSHEE 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
