; Z-Police level 27: LEVEL27.TXL, the text form of LEVEL27.ZPL
; The source is levels/LEVEL27.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 27
CITY 6
NAME ROME
ZOMBIES 20
WAVES 2
FAST 20
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 8
WAVE 2 BANSHEE 8

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
