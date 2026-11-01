; Z-Police level 1: LEVEL01.TXL, the text form of LEVEL01.ZPL
; The source is levels/LEVEL01.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 1
CITY 1
NAME LONDON
ZOMBIES 10
WAVES 1
FAST 1
VIEW 6

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
