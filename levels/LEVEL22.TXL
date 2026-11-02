; Z-Police level 22: LEVEL22.TXL, the text form of LEVEL22.ZPL
; The source is levels/LEVEL22.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 22
CITY 5
NAME BERLIN
ZOMBIES 15
WAVES 5
FAST 11
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1 GHOST 5 GHOUL 1
WAVE 2 BANSHEE 2
WAVE 3 GHOUL 1
WAVE 4 BANSHEE 2
WAVE 5 GHOUL 1

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
