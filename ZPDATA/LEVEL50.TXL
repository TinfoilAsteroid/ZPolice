; Z-Police level 50: LEVEL50.TXL, the text form of LEVEL50.ZPL
; The source is levels/LEVEL50.TXL: edit that one, then build.bat
; (gentables.py checks it and makes ZPDATA/ from it; its comments have
; the format)
LEVEL 50
CITY 10
NAME CHICAGO
ZOMBIES 10
WAVES 3
FAST 10
VIEW 8

; special monsters, one line a wave (1 is the level's start): WAVE n,
; then up to 5 type / count pairs; types: GHOST, BANSHEE, GHOUL, LICH, DEVIL, CLUSTERS
WAVE 1 BANSHEE 8
WAVE 2 LICH 8
WAVE 3 DEVIL 1

; cells of the city's map changed for this level: x z code family
CHANGES 37
11 49 . ..
12 49 . ..
13 49 . ..
10 50 . ..
11 50 . ..
12 50 . ..
13 50 . ..
14 50 . ..
9 51 . ..
10 51 . ..
11 51 . ..
12 51 . ..
13 51 . ..
14 51 . ..
15 51 . ..
9 52 . ..
10 52 . ..
11 52 . ..
12 52 . ..
13 52 . ..
14 52 . ..
15 52 . ..
9 53 . ..
10 53 . ..
11 53 . ..
12 53 . ..
13 53 . ..
14 53 . ..
15 53 . ..
10 54 . ..
11 54 . ..
12 54 . ..
13 54 . ..
14 54 . ..
11 55 . ..
12 55 . ..
13 55 . ..
END
