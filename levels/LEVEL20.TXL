; Z-Police level 20: LEVEL20.TXL, the text form of LEVEL20.ZPL
; The source is levels/LEVEL20.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 20
CITY 4
NAME NEW YORK
ZOMBIES 30
WAVES 4
FAST 10
VIEW 6

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL
WAVE 1 GHOST 5
WAVE 2 BANSHEE 2
WAVE 3
WAVE 4 BANSHEE 2

; cells of the city's map changed for this level: x z code family
CHANGES 0
END
