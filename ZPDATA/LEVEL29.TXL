; Z-Police level 29: LEVEL29.TXL, the text form of LEVEL29.ZPL
; The source is levels/LEVEL29.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 29
CITY 6
NAME ROME
ZOMBIES 25
WAVES 6
FAST 15
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1 GHOST 5 GHOUL 1
WAVE 2 BANSHEE 2
WAVE 3 GHOUL 1
WAVE 4 BANSHEE 2
WAVE 5 GHOUL 1
WAVE 6 BANSHEE 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
