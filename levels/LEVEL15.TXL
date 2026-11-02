; Z-Police level 15: LEVEL15.TXL, the text form of LEVEL15.ZPL
; The source is levels/LEVEL15.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 15
CITY 3
NAME TOKYO
ZOMBIES 30
WAVES 3
FAST 8
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1 GHOST 5
WAVE 2 BANSHEE 2
WAVE 3

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
