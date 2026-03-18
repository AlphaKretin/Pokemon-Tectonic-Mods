# Imports custom fusion front-battle sprites from a Pokemon Infinite Fusion
# installation into the Tectonic fusion sprite cache.
#
# Infinite Fusion stores custom sprites as spritesheets:
#   Graphics/CustomBattlers/spritesheets/spritesheets_custom/<head>/<head>.png
#
# Each spritesheet covers all fusions of that head species with every possible
# body.  Sprites are laid out in a GRID_WIDTH-wide grid, 0-indexed: cell N
# = the fusion whose body Pokemon has National Pokédex number N.  Cell 0 is
# always blank (no Pokemon #0).  The grid fills left-to-right, top-to-bottom.
#
# To use:
#   1. Copy Infinite Fusion's CustomBattlers folder (or just the
#      spritesheets_custom subfolder) into the game's Graphics/ folder so the
#      full path below exists.
#   2. Launch the game (so MKXP's path cache indexes the new files).
#   3. Open the debug menu → Other options → Import Infinite Fusion Sprites.
#
# Rules:
#   • Only front-battle sprites are imported (IF has no separate back sprites).
#   • Blank cells (all-transparent) are skipped.
#   • Species with no matching Tectonic ID are skipped.
#   • Existing files are never overwritten — custom sprites placed by the user
#     are left untouched.

module InfiniteFusionImport
    # Location of the Infinite Fusion spritesheets_custom folder within the
    # game's file tree.  Adjust if you place the files elsewhere.
    SOURCE_DIR = "Graphics/CustomBattlers/spritesheets/spritesheets_custom"

    # Number of sprite columns per row in every Infinite Fusion spritesheet.
    GRID_WIDTH = 20

    # Pixel stride used when sampling a cell for blank detection.
    # A smaller value is more accurate but slower; 6 works well for 96px sprites.
    SAMPLE_STRIDE = 6

    # Integer scale applied to every extracted sprite before saving.
    # IF custom sprites are 96×96.  Back sprites in Tectonic are 192×192
    # (exactly 2×), and front sprites are 160×160 (no clean integer scale from
    # 96), so 2× is used for both — front sprites end up at 192×192, which the
    # battle system handles fine via metrics.
    IMPORT_SCALE = 2

    # Maps each Infinite Fusion Pokédex number to the corresponding Tectonic
    # species and form.  IF has its own Pokédex order (differing from both the
    # National Dex and Tectonic's order), so this table must be filled in
    # manually.
    #
    # Format:  IF_dex_number => [TECTONIC_SPECIES_ID, form_int]
    #
    # form_int is 0 for the base form.  Use a non-zero value for alternate
    # forms that IF gives a separate Pokédex number (e.g. Castform-Rainy,
    # Minior-Red).  The form is encoded into the fusion filename by the same
    # scheme Tectonic uses internally, so the game will find the sprite
    # automatically.
    #
    # Omit any entry whose species does not exist in Tectonic.
    DEX_MAP = {
        
1 => [:BULBASAUR, 0],
2 => [:IVYSAUR, 0],
3 => [:VENUSAUR, 0],
4 => [:CHARMANDER, 0],
5 => [:CHARMELEON, 0],
6 => [:CHARIZARD, 0],
7 => [:SQUIRTLE, 0],
8 => [:WARTORTLE, 0],
9 => [:BLASTOISE, 0],
10 => [:CATERPIE, 0],
11 => [:METAPOD, 0],
12 => [:BUTTERFREE, 0],
13 => [:WEEDLE, 0],
14 => [:KAKUNA, 0],
15 => [:BEEDRILL, 0],
16 => [:PIDGEY, 0],
17 => [:PIDGEOTTO, 0],
18 => [:PIDGEOT, 0],
19 => [:RATTATA, 0],
20 => [:RATICATE, 0],
21 => [:SPEAROW, 0],
22 => [:FEAROW, 0],
23 => [:EKANS, 0],
24 => [:ARBOK, 0],
25 => [:PIKACHU, 0],
26 => [:RAICHU, 0],
27 => [:SANDSHREW, 0],
28 => [:SANDSLASH, 0],
29 => [:NIDORANmA, 0],
30 => [:NIDORINA, 0],
31 => [:NIDOQUEEN, 0],
32 => [:NIDORANfE, 0],
33 => [:NIDORINO, 0],
34 => [:NIDOKING, 0],
35 => [:CLEFAIRY, 0],
36 => [:CLEFABLE, 0],
37 => [:VULPIX, 0],
38 => [:NINETALES, 0],
39 => [:JIGGLYPUFF, 0],
40 => [:WIGGLYTUFF, 0],
41 => [:ZUBAT, 0],
42 => [:GOLBAT, 0],
43 => [:ODDISH, 0],
44 => [:GLOOM, 0],
45 => [:VILEPLUME, 0],
46 => [:PARAS, 0],
47 => [:PARASECT, 0],
48 => [:VENONAT, 0],
49 => [:VENOMOTH, 0],
50 => [:DIGLETT, 0],
51 => [:DUGTRIO, 0],
52 => [:MEOWTH, 0],
53 => [:PERSIAN, 0],
54 => [:PSYDUCK, 0],
55 => [:GOLDUCK, 0],
56 => [:MANKEY, 0],
57 => [:PRIMEAPE, 0],
58 => [:GROWLITHE, 0],
59 => [:ARCANINE, 0],
60 => [:POLIWAG, 0],
61 => [:POLIWHIRL, 0],
62 => [:POLIWRATH, 0],
63 => [:ABRA, 0],
64 => [:KADABRA, 0],
65 => [:ALAKAZAM, 0],
66 => [:MACHOP, 0],
67 => [:MACHOKE, 0],
68 => [:MACHAMP, 0],
69 => [:BELLSPROUT, 0],
70 => [:WEEPINBELL, 0],
71 => [:VICTREEBEL, 0],
72 => [:TENTACOOL, 0],
73 => [:TENTACRUEL, 0],
74 => [:GEODUDE, 0],
75 => [:GRAVELER, 0],
76 => [:GOLEM, 0],
77 => [:PONYTA, 0],
78 => [:RAPIDASH, 0],
79 => [:SLOWPOKE, 0],
80 => [:SLOWBRO, 0],
81 => [:MAGNEMITE, 0],
82 => [:MAGNETON, 0],
83 => [:FARFETCHD, 0],
84 => [:DODUO, 0],
85 => [:DODRIO, 0],
86 => [:SEEL, 0],
87 => [:DEWGONG, 0],
88 => [:GRIMER, 0],
89 => [:MUK, 0],
90 => [:SHELLDER, 0],
91 => [:CLOYSTER, 0],
92 => [:GASTLY, 0],
93 => [:HAUNTER, 0],
94 => [:GENGAR, 0],
95 => [:ONIX, 0],
96 => [:DROWZEE, 0],
97 => [:HYPNO, 0],
98 => [:KRABBY, 0],
99 => [:KINGLER, 0],
100 => [:VOLTORB, 0],
101 => [:ELECTRODE, 0],
102 => [:EXEGGCUTE, 0],
103 => [:EXEGGUTOR, 0],
104 => [:CUBONE, 0],
105 => [:MAROWAK, 0],
106 => [:HITMONLEE, 0],
107 => [:HITMONCHAN, 0],
108 => [:LICKITUNG, 0],
109 => [:KOFFING, 0],
110 => [:WEEZING, 0],
111 => [:RHYHORN, 0],
112 => [:RHYDON, 0],
113 => [:CHANSEY, 0],
114 => [:TANGELA, 0],
115 => [:KANGASKHAN, 0],
116 => [:HORSEA, 0],
117 => [:SEADRA, 0],
118 => [:GOLDEEN, 0],
119 => [:SEAKING, 0],
120 => [:STARYU, 0],
121 => [:STARMIE, 0],
122 => [:MRMIME, 0],
123 => [:SCYTHER, 0],
124 => [:JYNX, 0],
125 => [:ELECTABUZZ, 0],
126 => [:MAGMAR, 0],
127 => [:PINSIR, 0],
128 => [:TAUROS, 0],
129 => [:MAGIKARP, 0],
130 => [:GYARADOS, 0],
131 => [:LAPRAS, 0],
132 => [:DITTO, 0],
133 => [:EEVEE, 0],
134 => [:VAPOREON, 0],
135 => [:JOLTEON, 0],
136 => [:FLAREON, 0],
137 => [:PORYGON, 0],
138 => [:OMANYTE, 0],
139 => [:OMASTAR, 0],
140 => [:KABUTO, 0],
141 => [:KABUTOPS, 0],
142 => [:AERODACTYL, 0],
143 => [:SNORLAX, 0],
144 => [:ARTICUNO, 0],
145 => [:ZAPDOS, 0],
146 => [:MOLTRES, 0],
147 => [:DRATINI, 0],
148 => [:DRAGONAIR, 0],
149 => [:DRAGONITE, 0],
150 => [:MEWTWO, 0],
151 => [:MEW, 0],
152 => [:CHIKORITA, 0],
153 => [:BAYLEEF, 0],
154 => [:MEGANIUM, 0],
155 => [:CYNDAQUIL, 0],
156 => [:QUILAVA, 0],
157 => [:TYPHLOSION, 0],
158 => [:TOTODILE, 0],
159 => [:CROCONAW, 0],
160 => [:FERALIGATR, 0],
161 => [:SENTRET, 0],
162 => [:FURRET, 0],
163 => [:HOOTHOOT, 0],
164 => [:NOCTOWL, 0],
165 => [:LEDYBA, 0],
166 => [:LEDIAN, 0],
167 => [:SPINARAK, 0],
168 => [:ARIADOS, 0],
169 => [:CROBAT, 0],
170 => [:CHINCHOU, 0],
171 => [:LANTURN, 0],
172 => [:PICHU, 0],
173 => [:CLEFFA, 0],
174 => [:IGGLYBUFF, 0],
175 => [:TOGEPI, 0],
176 => [:TOGETIC, 0],
177 => [:NATU, 0],
178 => [:XATU, 0],
179 => [:MAREEP, 0],
180 => [:FLAAFFY, 0],
181 => [:AMPHAROS, 0],
182 => [:BELLOSSOM, 0],
183 => [:MARILL, 0],
184 => [:AZUMARILL, 0],
185 => [:SUDOWOODO, 0],
186 => [:POLITOED, 0],
187 => [:HOPPIP, 0],
188 => [:SKIPLOOM, 0],
189 => [:JUMPLUFF, 0],
190 => [:AIPOM, 0],
191 => [:SUNKERN, 0],
192 => [:SUNFLORA, 0],
193 => [:YANMA, 0],
194 => [:WOOPER, 0],
195 => [:QUAGSIRE, 0],
196 => [:ESPEON, 0],
197 => [:UMBREON, 0],
198 => [:MURKROW, 0],
199 => [:SLOWKING, 0],
200 => [:MISDREAVUS, 0],
201 => [:UNOWN, 0],
202 => [:WOBBUFFET, 0],
203 => [:GIRAFARIG, 0],
204 => [:PINECO, 0],
205 => [:FORRETRESS, 0],
206 => [:DUNSPARCE, 0],
207 => [:GLIGAR, 0],
208 => [:STEELIX, 0],
209 => [:SNUBBULL, 0],
210 => [:GRANBULL, 0],
211 => [:QWILFISH, 0],
212 => [:SCIZOR, 0],
213 => [:SHUCKLE, 0],
214 => [:HERACROSS, 0],
215 => [:SNEASEL, 0],
216 => [:TEDDIURSA, 0],
217 => [:URSARING, 0],
218 => [:SLUGMA, 0],
219 => [:MAGCARGO, 0],
220 => [:SWINUB, 0],
221 => [:PILOSWINE, 0],
222 => [:CORSOLA, 0],
223 => [:REMORAID, 0],
224 => [:OCTILLERY, 0],
225 => [:DELIBIRD, 0],
226 => [:MANTINE, 0],
227 => [:SKARMORY, 0],
228 => [:HOUNDOUR, 0],
229 => [:HOUNDOOM, 0],
230 => [:KINGDRA, 0],
231 => [:PHANPY, 0],
232 => [:DONPHAN, 0],
233 => [:PORYGON2, 0],
234 => [:STANTLER, 0],
235 => [:SMEARGLE, 0],
236 => [:TYROGUE, 0],
237 => [:HITMONTOP, 0],
238 => [:SMOOCHUM, 0],
239 => [:ELEKID, 0],
240 => [:MAGBY, 0],
241 => [:MILTANK, 0],
242 => [:BLISSEY, 0],
243 => [:RAIKOU, 0],
244 => [:ENTEI, 0],
245 => [:SUICUNE, 0],
246 => [:LARVITAR, 0],
247 => [:PUPITAR, 0],
248 => [:TYRANITAR, 0],
249 => [:LUGIA, 0],
250 => [:HOOH, 0],
251 => [:CELEBI, 0],
252 => [:AZURILL, 0],
253 => [:WYNAUT, 0],
254 => [:AMBIPOM, 0],
255 => [:MISMAGIUS, 0],
256 => [:HONCHKROW, 0],
257 => [:BONSLY, 0],
258 => [:MIMEJR, 0],
259 => [:HAPPINY, 0],
260 => [:MUNCHLAX, 0],
261 => [:MANTYKE, 0],
262 => [:WEAVILE, 0],
263 => [:MAGNEZONE, 0],
264 => [:LICKILICKY, 0],
265 => [:RHYPERIOR, 0],
266 => [:TANGROWTH, 0],
267 => [:ELECTIVIRE, 0],
268 => [:MAGMORTAR, 0],
269 => [:TOGEKISS, 0],
270 => [:YANMEGA, 0],
271 => [:LEAFEON, 0],
272 => [:GLACEON, 0],
273 => [:GLISCOR, 0],
274 => [:MAMOSWINE, 0],
275 => [:PORYGONZ, 0],
276 => [:TREECKO, 0],
277 => [:GROVYLE, 0],
278 => [:SCEPTILE, 0],
279 => [:TORCHIC, 0],
280 => [:COMBUSKEN, 0],
281 => [:BLAZIKEN, 0],
282 => [:MUDKIP, 0],
283 => [:MARSHTOMP, 0],
284 => [:SWAMPERT, 0],
285 => [:RALTS, 0],
286 => [:KIRLIA, 0],
287 => [:GARDEVOIR, 0],
288 => [:GALLADE, 0],
289 => [:SHEDINJA, 0],
290 => [:KECLEON, 0],
291 => [:BELDUM, 0],
292 => [:METANG, 0],
293 => [:METAGROSS, 0],
294 => [:BIDOOF, 0],
295 => [:SPIRITOMB, 0],
296 => [:LUCARIO, 0],
297 => [:GIBLE, 0],
298 => [:GABITE, 0],
299 => [:GARCHOMP, 0],
300 => [:MAWILE, 0],
301 => [:LILEEP, 0],
302 => [:CRADILY, 0],
303 => [:ANORITH, 0],
304 => [:ARMALDO, 0],
305 => [:CRANIDOS, 0],
306 => [:RAMPARDOS, 0],
307 => [:SHIELDON, 0],
308 => [:BASTIODON, 0],
309 => [:SLAKING, 0],
310 => [:ABSOL, 0],
311 => [:DUSKULL, 0],
312 => [:DUSCLOPS, 0],
313 => [:DUSKNOIR, 0],
314 => [:WAILORD, 0],
315 => [:ARCEUS, 0],
316 => [:TURTWIG, 0],
317 => [:GROTLE, 0],
318 => [:TORTERRA, 0],
319 => [:CHIMCHAR, 0],
320 => [:MONFERNO, 0],
321 => [:INFERNAPE, 0],
322 => [:PIPLUP, 0],
323 => [:PRINPLUP, 0],
324 => [:EMPOLEON, 0],
325 => [:NOSEPASS, 0],
326 => [:PROBOPASS, 0],
327 => [:HONEDGE, 0],
328 => [:DOUBLADE, 0],
329 => [:AEGISLASH, 0],
330 => [:PAWNIARD, 0],
331 => [:BISHARP, 0],
332 => [:LUXRAY, 0],
333 => [:AGGRON, 0],
334 => [:FLYGON, 0],
335 => [:MILOTIC, 0],
336 => [:SALAMENCE, 0],
337 => [:KLINKLANG, 0],
338 => [:ZOROARK, 0],
339 => [:SYLVEON, 0],
340 => [:KYOGRE, 0],
341 => [:GROUDON, 0],
342 => [:RAYQUAZA, 0],
343 => [:DIALGA, 0],
344 => [:PALKIA, 0],
345 => [:GIRATINA, 0],
346 => [:REGIGIGAS, 0],
347 => [:DARKRAI, 0],
348 => [:GENESECT, 0],
349 => [:RESHIRAM, 0],
350 => [:ZEKROM, 0],
351 => [:KYUREM, 0],
352 => [:ROSERADE, 0],
353 => [:DRIFBLIM, 0],
354 => [:LOPUNNY, 0],
355 => [:BRELOOM, 0],
356 => [:NINJASK, 0],
357 => [:BANETTE, 0],
358 => [:ROTOM, 0],
359 => [:REUNICLUS, 0],
360 => [:WHIMSICOTT, 0],
361 => [:KROOKODILE, 0],
362 => [:COFAGRIGUS, 0],
363 => [:GALVANTULA, 0],
364 => [:FERROTHORN, 0],
365 => [:LITWICK, 0],
366 => [:LAMPENT, 0],
367 => [:CHANDELURE, 0],
368 => [:HAXORUS, 0],
369 => [:GOLURK, 0],
370 => [:PYUKUMUKU, 0],
371 => [:KLEFKI, 0],
372 => [:TALONFLAME, 0],
373 => [:MIMIKYU, 0],
374 => [:VOLCARONA, 0],
375 => [:DEINO, 0],
376 => [:ZWEILOUS, 0],
377 => [:HYDREIGON, 0],
378 => [:LATIAS, 0],
379 => [:LATIOS, 0],
380 => [:DEOXYS, 0],
381 => [:JIRACHI, 0],
382 => [:NINCADA, 0],
383 => [:BIBAREL, 0],
384 => [:RIOLU, 0],
385 => [:SLAKOTH, 0],
386 => [:VIGOROTH, 0],
387 => [:WAILMER, 0],
388 => [:SHINX, 0],
389 => [:LUXIO, 0],
390 => [:ARON, 0],
391 => [:LAIRON, 0],
392 => [:TRAPINCH, 0],
393 => [:VIBRAVA, 0],
394 => [:FEEBAS, 0],
395 => [:BAGON, 0],
396 => [:SHELGON, 0],
397 => [:KLINK, 0],
398 => [:KLANG, 0],
399 => [:ZORUA, 0],
400 => [:BUDEW, 0],
401 => [:ROSELIA, 0],
402 => [:DRIFLOON, 0],
403 => [:BUNEARY, 0],
404 => [:SHROOMISH, 0],
405 => [:SHUPPET, 0],
406 => [:SOLOSIS, 0],
407 => [:DUOSION, 0],
408 => [:COTTONEE, 0],
409 => [:SANDILE, 0],
410 => [:KROKOROK, 0],
411 => [:YAMASK, 0],
412 => [:JOLTIK, 0],
413 => [:FERROSEED, 0],
414 => [:AXEW, 0],
415 => [:FRAXURE, 0],
416 => [:GOLETT, 0],
417 => [:FLETCHLING, 0],
418 => [:FLETCHINDER, 0],
419 => [:LARVESTA, 0],
420 => [:STUNFISK, 0],
421 => [:SABLEYE, 0],
422 => [:VENIPEDE, 0],
423 => [:WHIRLIPEDE, 0],
424 => [:SCOLIPEDE, 0],
425 => [:TYRUNT, 0],
426 => [:TYRANTRUM, 0],
427 => [:SNORUNT, 0],
428 => [:GLALIE, 0],
429 => [:FROSLASS, 0],
430 => [:ORICORIO, 0],
431 => [:ORICORIO, 1],
432 => [:ORICORIO, 2],
433 => [:ORICORIO, 3],
434 => [:TRUBBISH, 0],
435 => [:GARBODOR, 0],
436 => [:CARVANHA, 0],
437 => [:SHARPEDO, 0],
438 => [:PHANTUMP, 0],
439 => [:TREVENANT, 0],
440 => [:NOIBAT, 0],
441 => [:NOIVERN, 0],
442 => [:SWABLU, 0],
443 => [:ALTARIA, 0],
444 => [:GOOMY, 0],
445 => [:SLIGGOO, 0],
446 => [:GOODRA, 0],
447 => [:REGIROCK, 0],
448 => [:REGICE, 0],
449 => [:REGISTEEL, 0],
450 => [:NECROZMA, 0],
451 => [:STUFFUL, 0],
452 => [:BEWEAR, 0],
453 => [:DHELMISE, 0],
454 => [:MAREANIE, 0],
455 => [:TOXAPEX, 0],
456 => [:HAWLUCHA, 0],
457 => [:CACNEA, 0],
458 => [:CACTURNE, 0],
459 => [:SANDYGAST, 0],
460 => [:PALOSSAND, 0],
461 => [:AMAURA, 0],
462 => [:AURORUS, 0],
463 => [:ROCKRUFF, 0],
464 => [:LYCANROC, 0],
465 => [:WOLFEROC, 0],
466 => [:MELOETTA, 0],
467 => [:MELOETTA, 1],
468 => [:CRESSELIA, 0],
469 => [:BRUXISH, 0],
470 => [:NECROZMA, 4],
471 => [:JANGMOO, 0],
472 => [:HAKAMOO, 0],
473 => [:KOMMOO, 0],
474 => [:WIMPOD, 0],
475 => [:GOLISOPOD, 0],
476 => [:FOMANTIS, 0],
477 => [:LURANTIS, 0],
478 => [:CARBINK, 0],
479 => [:CHESPIN, 0],
480 => [:QUILLADIN, 0],
481 => [:CHESNAUGHT, 0],
482 => [:FENNEKIN, 0],
483 => [:BRAIXEN, 0],
484 => [:DELPHOX, 0],
485 => [:FROAKIE, 0],
486 => [:FROGADIER, 0],
487 => [:GRENINJA, 0],
488 => [:TORKOAL, 0],
489 => [:PUMPKABOO, 0],
490 => [:GOURGEIST, 0],
491 => [:SWIRLIX, 0],
492 => [:SLURPUFF, 0],
493 => [:SCRAGGY, 0],
494 => [:SCRAFTY, 0],
495 => [:LOTAD, 0],
496 => [:LOMBRE, 0],
497 => [:LUDICOLO, 0],
498 => [:MINIOR, 0],
499 => [:MINIOR, 7],
500 => [:DIANCIE, 0],
501 => [:LUVDISC, 0],
502 => [:POOCHYENA, 0],
503 => [:MIGHTYENA, 0],
504 => [:ZIGZAGOON, 0],
505 => [:LINOONE, 0],
506 => [:WURMPLE, 0],
507 => [:SILCOON, 0],
508 => [:BEAUTIFLY, 0],
509 => [:CASCOON, 0],
510 => [:DUSTOX, 0],
511 => [:SEEDOT, 0],
512 => [:NUZLEAF, 0],
513 => [:SHIFTRY, 0],
514 => [:TAILLOW, 0],
515 => [:SWELLOW, 0],
516 => [:WINGULL, 0],
517 => [:PELIPPER, 0],
518 => [:SURSKIT, 0],
519 => [:MASQUERAIN, 0],
520 => [:WHISMUR, 0],
521 => [:LOUDRED, 0],
522 => [:EXPLOUD, 0],
523 => [:MAKUHITA, 0],
524 => [:HARIYAMA, 0],
525 => [:SKITTY, 0],
526 => [:DELCATTY, 0],
527 => [:MEDITITE, 0],
528 => [:MEDICHAM, 0],
529 => [:ELECTRIKE, 0],
530 => [:MANECTRIC, 0],
531 => [:PLUSLE, 0],
532 => [:MINUN, 0],
533 => [:VOLBEAT, 0],
534 => [:ILLUMISE, 0],
535 => [:GULPIN, 0],
536 => [:SWALOT, 0],
537 => [:NUMEL, 0],
538 => [:CAMERUPT, 0],
539 => [:SPOINK, 0],
540 => [:GRUMPIG, 0],
541 => [:SPINDA, 0],
542 => [:ZANGOOSE, 0],
543 => [:SEVIPER, 0],
544 => [:LUNATONE, 0],
545 => [:SOLROCK, 0],
546 => [:BARBOACH, 0],
547 => [:WHISCASH, 0],
548 => [:CORPHISH, 0],
549 => [:CRAWDAUNT, 0],
550 => [:BALTOY, 0],
551 => [:CLAYDOL, 0],
552 => [:CASTFORM, 0],
553 => [:CASTFORM, 1],
554 => [:CASTFORM, 2],
555 => [:CASTFORM, 3],
556 => [:TROPIUS, 0],
557 => [:CHINGLING, 0],
558 => [:CHIMECHO, 0],
559 => [:SPHEAL, 0],
560 => [:SEALEO, 0],
561 => [:WALREIN, 0],
562 => [:CLAMPERL, 0],
563 => [:HUNTAIL, 0],
564 => [:GOREBYSS, 0],
565 => [:RELICANTH, 0],
566 => [:WOOBAT, 0],
567 => [:SWOOBAT, 0],
568 => [:TYNAMO, 0],
569 => [:EELEKTRIK, 0],
570 => [:EELEKTROSS, 0],
571 => [:SKRELP, 0],
572 => [:DRAGALGE, 0]
    }.freeze

    # ── Helpers ───────────────────────────────────────────────────────────────

    # Returns a new BitmapWrapper that is +bm+ flipped horizontally.
    # Uses 1-pixel-wide column blits rather than per-pixel access for speed.
    # The caller is responsible for disposing the result.
    def self.mirror_horizontal(bm)
        w      = bm.width
        h      = bm.height
        result = BitmapWrapper.new(w, h)
        w.times { |x| result.blt(w - 1 - x, 0, bm, Rect.new(x, 0, 1, h)) }
        result
    end

    # Returns true when every sampled pixel in the rectangle (x, y, w, h) of
    # +bm+ is fully transparent (alpha == 0).
    def self.blank_region?(bm, x, y, w, h)
        sy = y
        while sy < y + h
            sx = x
            while sx < x + w
                return false if bm.get_pixel(sx, sy).alpha > 0
                sx += SAMPLE_STRIDE
            end
            sy += SAMPLE_STRIDE
        end
        true
    end

    # ── Main import ───────────────────────────────────────────────────────────

    def self.run
        unless File.directory?(SOURCE_DIR)
            pbMessage(_INTL(
                "Infinite Fusion sprite folder not found:\n{1}\n\n" \
                "Copy the Infinite Fusion spritesheets_custom folder " \
                "there, restart the game, then try again.",
                SOURCE_DIR
            ))
            return
        end

        saved    = 0
        skipped  = 0  # blank cell or no Tectonic species for that dex number
        existing = 0  # file already present — left alone

        front_dir = FusionSprites::FRONT_DIR
        back_dir  = FusionSprites::BACK_DIR
        FusionSprites.ensure_dir(front_dir)
        FusionSprites.ensure_dir(back_dir)

        total_sheets = Dir.glob("#{SOURCE_DIR}/*/").count
        sheet_num    = 0

        Dir.glob("#{SOURCE_DIR}/*").sort.each do |head_dir|
            next unless File.directory?(head_dir)

            head_dex = File.basename(head_dir).to_i
            next if head_dex == 0

            primary_entry = DEX_MAP[head_dex]
            next unless primary_entry
            primary_sym, primary_form = primary_entry

            sheet_path = "#{head_dir}/#{head_dex}.png"
            next unless File.exist?(sheet_path)

            sheet_num  += 1
            sheet_saved = 0

            # Bitmap.new works here because these files exist at game startup
            # and are therefore indexed by MKXP's path cache.
            sheet_bm = Bitmap.new(sheet_path)
            next unless sheet_bm && !sheet_bm.disposed?

            sprite_w = sheet_bm.width / GRID_WIDTH
            sprite_h = sprite_w   # Infinite Fusion custom sprites are square
            num_rows = sheet_bm.height / sprite_h
            num_cells = num_rows * GRID_WIDTH

            # Body index 0 = "no Pokemon" — always blank, always skip.
            (1...num_cells).each do |body_idx|
                secondary_entry = DEX_MAP[body_idx]
                unless secondary_entry
                    skipped += 1
                    next
                end
                secondary_sym, secondary_form = secondary_entry

                col = body_idx % GRID_WIDTH
                row = body_idx / GRID_WIDTH
                sx  = col * sprite_w
                sy  = row * sprite_h

                # Guard against sheets whose height is not an exact multiple.
                if sy + sprite_h > sheet_bm.height
                    skipped += 1
                    next
                end

                if blank_region?(sheet_bm, sx, sy, sprite_w, sprite_h)
                    skipped += 1
                    next
                end

                fusion_id     = :"#{primary_sym}_#{secondary_sym}"
                encoded_form  = primary_form * GameData::FusedSpecies.count_forms(secondary_sym) \
                                + secondary_form
                front_path = FusionSprites.cache_path(fusion_id, encoded_form, front_dir) + ".png"
                back_path  = FusionSprites.cache_path(fusion_id, encoded_form, back_dir)  + ".png"

                front_exists = File.exist?(front_path)
                back_exists  = File.exist?(back_path)
                if front_exists && back_exists
                    existing += 1
                    next
                end

                out_w     = sprite_w * IMPORT_SCALE
                out_h     = sprite_h * IMPORT_SCALE
                sprite_bm = BitmapWrapper.new(out_w, out_h)
                sprite_bm.stretch_blt(Rect.new(0, 0, out_w, out_h), sheet_bm, Rect.new(sx, sy, sprite_w, sprite_h))
                sprite_bm.to_file(front_path) unless front_exists
                unless back_exists
                    back_bm = mirror_horizontal(sprite_bm)
                    back_bm.to_file(back_path)
                    back_bm.dispose
                end
                sprite_bm.dispose
                saved       += 1
                sheet_saved += 1
            end

            sheet_bm.dispose
            echoln "[IF Import] #{sheet_num}/#{total_sheets} #{primary_sym} (IF ##{head_dex}): #{sheet_saved} saved (#{saved} total)"
        end

        pbMessage(_INTL(
            "Import complete.\nSaved: {1}  Skipped: {2}  Unchanged: {3}",
            saved, skipped, existing
        ))
    end
end

DebugMenuCommands.register("importifsprites", {
    "parent"      => "othermenu",
    "name"        => _INTL("Import Infinite Fusion Sprites"),
    "description" => _INTL(
        "Import front battle sprites from Pokemon Infinite Fusion."
    ),
    "always_show" => true,
    "effect"      => proc { InfiniteFusionImport.run }
})
