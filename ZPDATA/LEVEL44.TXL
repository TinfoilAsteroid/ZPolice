; Z-Police level 44: LEVEL44.TXL, the text form of LEVEL44.ZPL
; The source is levels/LEVEL44.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 44
CITY 9
NAME CAIRO
ZOMBIES 25
WAVES 9
FAST 22
VIEW 6

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1 GHOST 5 GHOUL 3
WAVE 2 BANSHEE 3
WAVE 3 GHOUL 3
WAVE 4 BANSHEE 3
WAVE 5 GHOUL 3
WAVE 6 BANSHEE 3
WAVE 7 GHOUL 3
WAVE 8 BANSHEE 3
WAVE 9 GHOUL 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
