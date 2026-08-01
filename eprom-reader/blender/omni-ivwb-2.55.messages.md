# Display message table: omni ivwb 2.55 u3.bin

One continuous table, base `$6AE2`, 18 bytes/entry (16-char text field +
`$00` + `$61` trailer pair), 130 entries (index 0-129), spanning
`$6AE2`-`$7406`. Found the same way as the dryer/FNX message tables in this
project - the linear-sweep disassembler misdecodes this region as bogus
instructions; the text was recovered by reading the raw bytes directly and
confirming the fixed stride.

Not yet cross-referenced against its lookup call sites in the code (unlike
the dryer's messages.md) - this is the raw extracted catalog only.

Confirms the device is a **gravimetric blender/feeder** for plastics
processing - recipe, component, fill-rate, and calibration terminology
throughout (`FILL-LBS`, `RATES IN LBS/HR`, `SELECT COMPONENT`,
`CALIBRATE`, `MIXER TIME`, `RECIPE RECALLED`, etc.) - not the hot air
resin dryer this project started with, though the same general plastics-
processing-auxiliary-equipment category, consistent with also speaking an
SPI-CCP-family protocol (see omni-ivwb-2.55.protocol.md).

| Index | Addr | Text |
|---|---|---|
| 0 | `$6ae2` | `FILL-LBS =      ` |
| 1 | `$6af4` | `FILL-KGS =      ` |
| 2 | `$6b06` | ` LBS-  =        ` |
| 3 | `$6b18` | ` KGS-  =        ` |
| 4 | `$6b2a` | `TOTALS IN LBS   ` |
| 5 | `$6b3c` | `TOTALS IN KGS   ` |
| 6 | `$6b4e` | `PRESS 1-2-3 OR 4` |
| 7 | `$6b60` | `RATES IN LBS/HR ` |
| 8 | `$6b72` | `RATES IN KGS/HR ` |
| 9 | `$6b84` | `PERCENT OF MAX  ` |
| 10 | `$6b96` | `SET UP ERROR    ` |
| 11 | `$6ba8` | `REGRIND HI SET  ` |
| 12 | `$6bba` | `INVALID BLEND   ` |
| 13 | `$6bcc` | `CLEAR ALL? <Y/N>` |
| 14 | `$6bde` | `LOAD TIME =     ` |
| 15 | `$6bf0` | `RESTORE DEF<Y/N>` |
| 16 | `$6c02` | `1-EN 2-DIS =    ` |
| 17 | `$6c14` | `PERCNT CHANGE=  ` |
| 18 | `$6c26` | `MIXER TIME =    ` |
| 19 | `$6c38` | `START DELAY =%3d` |
| 20 | `$6c4a` | `SET MODE =      ` |
| 21 | `$6c5c` | `COMPONENT =     ` |
| 22 | `$6c6e` | `KEYPAD IS LOCKED` |
| 23 | `$6c80` | `RECOV COUNT =   ` |
| 24 | `$6c92` | `NORMAL MODE     ` |
| 25 | `$6ca4` | `RESTORING DEFS  ` |
| 26 | `$6cb6` | `BATCHSIZE=      ` |
| 27 | `$6cc8` | `FUNC NOT AVAIL  ` |
| 28 | `$6cda` | `* END OF ALARM *` |
| 29 | `$6cec` | `CLEARING ALARMS ` |
| 30 | `$6cfe` | `WT IN LBS=      ` |
| 31 | `$6d10` | `WT IN KGS=      ` |
| 32 | `$6d22` | `CLEAR ALMS FIRST` |
| 33 | `$6d34` | `SET RATE KEY    ` |
| 34 | `$6d46` | `FUNCTION KEY    ` |
| 35 | `$6d58` | `RUN/STOP KEY    ` |
| 36 | `$6d6a` | `VIEW ALARM KEY  ` |
| 37 | `$6d7c` | `CLEAR ALARM KEY ` |
| 38 | `$6d8e` | `STORE RECIPE KEY` |
| 39 | `$6da0` | `RECAL RECIPE KEY` |
| 40 | `$6db2` | `PRESS ANY KEY   ` |
| 41 | `$6dc4` | `KEY PRESSED =   ` |
| 42 | `$6dd6` | `STEP BACK KEY   ` |
| 43 | `$6de8` | `ENTER KEY       ` |
| 44 | `$6dfa` | `REG HI ACTIVE   ` |
| 45 | `$6e0c` | `REG HI INACTIVE ` |
| 46 | `$6e1e` | `ABORT BATCH? Y/N` |
| 47 | `$6e30` | `ARE YOU SURE Y/N` |
| 48 | `$6e42` | `ON = 1  OFF = 3 ` |
| 49 | `$6e54` | `ALARM TIME =    ` |
| 50 | `$6e66` | `PURGE 1-2-3 OR 4` |
| 51 | `$6e78` | `STORE RECIPE    ` |
| 52 | `$6e8a` | `RECIPE =000     ` |
| 53 | `$6e9c` | `MEMORY IS FULL  ` |
| 54 | `$6eae` | `RECIPE= --------` |
| 55 | `$6ec0` | `   =            ` |
| 56 | `$6ed2` | `NO MORE RECIPES ` |
| 57 | `$6ee4` | `RECIPE IS BLANK ` |
| 58 | `$6ef6` | `RECALL RECIPE   ` |
| 59 | `$6f08` | `RECIPE RECALLED ` |
| 60 | `$6f1a` | `** NO RECIPES **` |
| 61 | `$6f2c` | `RECIPE DELETED  ` |
| 62 | `$6f3e` | `RECIPES CLEARED ` |
| 63 | `$6f50` | `SHUTDOWN = YES  ` |
| 64 | `$6f62` | `SHUTDOWN = NO   ` |
| 65 | `$6f74` | `BELL ON  = YES  ` |
| 66 | `$6f86` | `BELL ON  = NO   ` |
| 67 | `$6f98` | `LIGHT ON = YES  ` |
| 68 | `$6faa` | `LIGHT ON = NO   ` |
| 69 | `$6fbc` | `LED ON   = YES  ` |
| 70 | `$6fce` | `LED ON   = NO   ` |
| 71 | `$6fe0` | `BEEPER   = YES  ` |
| 72 | `$6ff2` | `BEEPER   = NO   ` |
| 73 | `$7004` | `SETUP           ` |
| 74 | `$7016` | `CONFIGURE ALARMS` |
| 75 | `$7028` | `PASSWORDS       ` |
| 76 | `$703a` | `START BATCH     ` |
| 77 | `$704c` | `IGNORE LOW MATS ` |
| 78 | `$705e` | `RUN DIAGNOSTICS ` |
| 79 | `$7070` | `SHUT DIAGNOSTICS` |
| 80 | `$7082` | `OUTPUTS TEST    ` |
| 81 | `$7094` | `MOTOR DIAGNOSTIC` |
| 82 | `$70a6` | `DELIVER SAMPLE  ` |
| 83 | `$70b8` | `PURGE MATERIAL  ` |
| 84 | `$70ca` | `CAL WEIGHT CHECK` |
| 85 | `$70dc` | `LAMP TEST       ` |
| 86 | `$70ee` | `KEYPAD TEST     ` |
| 87 | `$7100` | `LEVEL SENSR TEST` |
| 88 | `$7112` | `LD CELL DIAG RAW` |
| 89 | `$7124` | `CHECK VERSION ID` |
| 90 | `$7136` | `LD CELL DIAG WT ` |
| 91 | `$7148` | `PASSWORD LEVEL  ` |
| 92 | `$715a` | `CHANGE PASSWORD ` |
| 93 | `$716c` | `NOT A FUNCTION  ` |
| 94 | `$717e` | `TEST DUMP VALVE ` |
| 95 | `$7190` | `TEST MIXER      ` |
| 96 | `$71a2` | `TEST ALARM BELL ` |
| 97 | `$71b4` | `TEST ALARM LIGHT` |
| 98 | `$71c6` | `TEST LOAD ENABLE` |
| 99 | `$71d8` | `VIEW TOTALS     ` |
| 100 | `$71ea` | `CLEAR TOTALS    ` |
| 101 | `$71fc` | `RUNNING TOTALS  ` |
| 102 | `$720e` | `DELIVERY RATE   ` |
| 103 | `$7220` | `FUNCTION=001    ` |
| 104 | `$7232` | `RECIPES         ` |
| 105 | `$7244` | `CALIBRATE       ` |
| 106 | `$7256` | `STATISTICS      ` |
| 107 | `$7268` | `FILL GAYLORD    ` |
| 108 | `$727a` | `CONFIGURE       ` |
| 109 | `$728c` | `DIAGNOSTIC DOCTR` |
| 110 | `$729e` | `DISPLAY RECIPES ` |
| 111 | `$72b0` | `DELETE RECIPES  ` |
| 112 | `$72c2` | `CLEAR RECIPES   ` |
| 113 | `$72d4` | `SET MODE        ` |
| 114 | `$72e6` | `SET BATCH SIZE  ` |
| 115 | `$72f8` | `EN/DIS ADAP. LOW` |
| 116 | `$730a` | `ADAP HGH SETTING` |
| 117 | `$731c` | `MIXER CONTROL   ` |
| 118 | `$732e` | `EN/DIS KEY BEEP ` |
| 119 | `$7340` | `ENGLISH/METRIC  ` |
| 120 | `$7352` | `RESTORE DEFAULTS` |
| 121 | `$7364` | `FUNCTION=001    ` |
| 122 | `$7376` | `RECIPES         ` |
| 123 | `$7388` | `CALIBRATE       ` |
| 124 | `$739a` | `STATISTICS      ` |
| 125 | `$73ac` | `FILL GAYLORD    ` |
| 126 | `$73be` | `CONFIGURE       ` |
| 127 | `$73d0` | `DIAGNOSTIC DOCTR` |
| 128 | `$73e2` | ` ENTER TO START ` |
| 129 | `$73f4` | `SELECT COMPONENT` |
