; Z-Police level 2: LEVEL02.TXL, the text form of LEVEL02.ZPL
; The source is levels/LEVEL02.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 2
CITY 1
NAME LONDON
ZOMBIES 15
WAVES 1
FAST 1
VIEW 6

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
