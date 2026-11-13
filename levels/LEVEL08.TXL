; Z-Police level 8: LEVEL08.TXL, the text form of LEVEL08.ZPL
; The source is levels/LEVEL08.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 8
CITY 2
NAME PARIS
ZOMBIES 20
WAVES 1
FAST 4
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 GHOST 4

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
