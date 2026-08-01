# Display message table: dryer-fnx-4.20-pct.bin

One continuous table, base `$E460`, 9 bytes/entry (8-char field + `$00` terminator),
193 entries (index 0-192), spanning `$E460`-`$EB28`. Confirmed as ONE table, not two -
an earlier pass mistakenly treated `$EA51` as a separate alarm-message table, but
`(0xEA51-0xE460)/9 = 169` exactly, and `0xEA00` (another apparent "table start") is
index 160 - both are just later offsets into this same table, reached via different
hardcoded base constants at different call sites rather than one shared routine.

Looked up throughout the code via the recurring pattern `index * 9 + $E460`
(a classic compiler-generated "array of fixed-width structs" index calculation -
see `dryer-fnx-4.20-pct.disassembly.txt` for the actual instruction sequences and
their addresses, roughly 15+ call sites). Different call sites hardcode a
pre-added base (e.g. `$EA51` for index 169, matching the alarm-message run
starting there) rather than always computing from index 0 - convenient for
callers that only ever need a sub-range (e.g. "just the alarm names").

Rough section boundaries (inferred from content, not from any structural marker -
the table itself has no section headers):
- 0-~140ish: main menu/status labels (setpoints, config, diagnostics, I/O names)
- ~160-192: alarm/fault condition names (`OVERTMP1`, `DEW SNSR`, `HOP1 LOW`, etc.)

A separate, structurally different table sits at `$E2B9`+ (9-byte binary records,
not text - hypothesized as per-parameter min/max/type metadata, not confirmed) and
another at `$E451` (3-byte records - handler+match-byte shape, likely a dispatch
table like `$0A28`, not text). Neither is included below.

| Index | Addr | Text |
|---|---|---|
| 0 | `$e460` | `        ` |
| 1 | `$e469` | `OFF     ` |
| 2 | `$e472` | `  SURE? ` |
| 3 | `$e47b` | `  N/A   ` |
| 4 | `$e484` | `MIN=    ` |
| 5 | `$e48d` | `MAX=    ` |
| 6 | `$e496` | `SP1=    ` |
| 7 | `$e49f` | `MS1=    ` |
| 8 | `$e4a8` | `FUNC 000` |
| 9 | `$e4b1` | `NO FUNC ` |
| 10 | `$e4ba` | `#T1=    ` |
| 11 | `$e4c3` | `#T2=    ` |
| 12 | `$e4cc` | `DPT= -  ` |
| 13 | `$e4d5` | `DPX=    ` |
| 14 | `$e4de` | `=       ` |
| 15 | `$e4e7` | ` =      ` |
| 16 | `$e4f0` | `DAY=    ` |
| 17 | `$e4f9` | `HOUR=   ` |
| 18 | `$e502` | `MIN=    ` |
| 19 | `$e50b` | `MSSP=   ` |
| 20 | `$e514` | `MS=     ` |
| 21 | `$e51d` | `INVAL MS` |
| 22 | `$e526` | `INVAL PW` |
| 23 | `$e52f` | `PW= ----` |
| 24 | `$e538` | `PWLVL=  ` |
| 25 | `$e541` | `NEW ----` |
| 26 | `$e54a` | `VFY ----` |
| 27 | `$e553` | `PW CHNG ` |
| 28 | `$e55c` | `NO MATCH` |
| 29 | `$e565` | `RESTART ` |
| 30 | `$e56e` | `QUIKSTRT` |
| 31 | `$e577` | `HRS=    ` |
| 32 | `$e580` | `CHNG    ` |
| 33 | `$e589` | `FATL=   ` |
| 34 | `$e592` | `OUTP=   ` |
| 35 | `$e59b` | `LED=    ` |
| 36 | `$e5a4` | `NOALARMS` |
| 37 | `$e5ad` | `END ALMS` |
| 38 | `$e5b6` | `FNX DHD ` |
| 39 | `$e5bf` | `VER ####` |
| 40 | `$e5c8` | `1 PROCHT` |
| 41 | `$e5d1` | `2 PROCHT` |
| 42 | `$e5da` | `STD DEW ` |
| 43 | `$e5e3` | `KAHN DEW` |
| 44 | `$e5ec` | `TRANSMET` |
| 45 | `$e5f5` | `SHAW SDG` |
| 46 | `$e5fe` | `````````` |
| 47 | `$e607` | `**WAIT**` |
| 48 | `$e610` | `HZ=     ` |
| 49 | `$e619` | `TEST    ` |
| 50 | `$e622` | `CE=     ` |
| 51 | `$e62b` | `DE=     ` |
| 52 | `$e634` | `IC=     ` |
| 53 | `$e63d` | `PC=     ` |
| 54 | `$e646` | `DC=     ` |
| 55 | `$e64f` | `T=      ` |
| 56 | `$e658` | `#T=     ` |
| 57 | `$e661` | `PARM=   ` |
| 58 | `$e66a` | `DELETE? ` |
| 59 | `$e673` | `END CMDS` |
| 60 | `$e67c` | `NO CMDS ` |
| 61 | `$e685` | `DELETED ` |
| 62 | `$e68e` | `MAX CMDS` |
| 63 | `$e697` | `CMD=    ` |
| 64 | `$e6a0` | `DEW=    ` |
| 65 | `$e6a9` | `ADD1=   ` |
| 66 | `$e6b2` | `ADD2=   ` |
| 67 | `$e6bb` | `BD=     ` |
| 68 | `$e6c4` | `PRG=    ` |
| 69 | `$e6cd` | `SEC=    ` |
| 70 | `$e6d6` | `GAS FR  ` |
| 71 | `$e6df` | `GAS UV  ` |
| 72 | `$e6e8` | `ELECPROC` |
| 73 | `$e6f1` | `GAS RGN ` |
| 74 | `$e6fa` | `ELEC RGN` |
| 75 | `$e703` | `SPI COMM` |
| 76 | `$e70c` | ` UD NET ` |
| 77 | `$e715` | `COOL    ` |
| 78 | `$e71e` | `PCNT=   ` |
| 79 | `$e727` | `OKST=   ` |
| 80 | `$e730` | `STD=    ` |
| 81 | `$e739` | `    TEMP` |
| 82 | `$e742` | `     DEW` |
| 83 | `$e74b` | `ALARM ##` |
| 84 | `$e754` | `  PCT2  ` |
| 85 | `$e75d` | `SETPOINT` |
| 86 | `$e766` | `STARTUP ` |
| 87 | `$e76f` | `SHUTDOWN` |
| 88 | `$e778` | `MORE -1-` |
| 89 | `$e781` | `MAT SAVR` |
| 90 | `$e78a` | `MS1RESET` |
| 91 | `$e793` | `MS1SETUP` |
| 92 | `$e79c` | `BATCHCMD` |
| 93 | `$e7a5` | `VIEW CLK` |
| 94 | `$e7ae` | `SETCLOCK` |
| 95 | `$e7b7` | `VIEWCMDS` |
| 96 | `$e7c0` | `NEW CMD ` |
| 97 | `$e7c9` | `PERM E/D` |
| 98 | `$e7d2` | `DEL CMD ` |
| 99 | `$e7db` | `DEL ALL ` |
| 100 | `$e7e4` | `#OVERTMP` |
| 101 | `$e7ed` | `DEW TRIG` |
| 102 | `$e7f6` | `DEW XTND` |
| 103 | `$e7ff` | `MORE -2-` |
| 104 | `$e808` | ` ALARMS ` |
| 105 | `$e811` | `PASSWORD` |
| 106 | `$e81a` | `PW LEVEL` |
| 107 | `$e823` | ` SET PW ` |
| 108 | `$e82c` | ` CONFIG ` |
| 109 | `$e835` | `DEG F/C ` |
| 110 | `$e83e` | `QUIKTIME` |
| 111 | `$e847` | `COOLDOWN` |
| 112 | `$e850` | `  SPI   ` |
| 113 | `$e859` | `ADDRESS ` |
| 114 | `$e862` | `  BAUD  ` |
| 115 | `$e86b` | ` MAX SP ` |
| 116 | `$e874` | `RSTRDEFS` |
| 117 | `$e87d` | `  SQC   ` |
| 118 | `$e886` | ` P1 AVG ` |
| 119 | `$e88f` | `P1 STDDV` |
| 120 | `$e898` | ` DP AVG ` |
| 121 | `$e8a1` | `DP STDDV` |
| 122 | `$e8aa` | `RESETSQC` |
| 123 | `$e8b3` | `DIAGNOSE` |
| 124 | `$e8bc` | `UNIT ID ` |
| 125 | `$e8c5` | `LAMPTEST` |
| 126 | `$e8ce` | ` TEMPS  ` |
| 127 | `$e8d7` | `PROCESS1` |
| 128 | `$e8e0` | `RETURN 1` |
| 129 | `$e8e9` | `REGENHTR` |
| 130 | `$e8f2` | `REGENOUT` |
| 131 | `$e8fb` | `DRYEROUT` |
| 132 | `$e904` | `DEWPOINT` |
| 133 | `$e90d` | `COMMDIAG` |
| 134 | `$e916` | `ADV CAM ` |
| 135 | `$e91f` | `OUTPUTS ` |
| 136 | `$e928` | `PROCBLWR` |
| 137 | `$e931` | `REGNBLWR` |
| 138 | `$e93a` | `VALVE 1 ` |
| 139 | `$e943` | `VALVE 2 ` |
| 140 | `$e94c` | `GASONOFF` |
| 141 | `$e955` | `RGN ISOL` |
| 142 | `$e95e` | `PROC1HTR` |
| 143 | `$e967` | `ALARMOUT` |
| 144 | `$e970` | `SERVICE ` |
| 145 | `$e979` | `NUM HTRS` |
| 146 | `$e982` | `HITURNDN` |
| 147 | `$e98b` | `GASPURGE` |
| 148 | `$e994` | `MPEEPTST` |
| 149 | `$e99d` | `CALIBRAT` |
| 150 | `$e9a6` | `AC INPUT` |
| 151 | `$e9af` | `DEW TYPE` |
| 152 | `$e9b8` | `PCT TYPE` |
| 153 | `$e9c1` | `HOPR LVL` |
| 154 | `$e9ca` | `PROCFLTR` |
| 155 | `$e9d3` | `RGN FLTR` |
| 156 | `$e9dc` | `  MISC  ` |
| 157 | `$e9e5` | ` P1 PID ` |
| 158 | `$e9ee` | `PROC HTR` |
| 159 | `$e9f7` | `PCT DIAG` |
| 160 | `$ea00` | `P THRMST` |
| 161 | `$ea09` | `R THRMST` |
| 162 | `$ea12` | `ALARMLOG` |
| 163 | `$ea1b` | `CLEARLOG` |
| 164 | `$ea24` | `VIEW LOG` |
| 165 | `$ea2d` | `VIEW CON` |
| 166 | `$ea36` | `CON LIFE` |
| 167 | `$ea3f` | `CLR HTR1` |
| 168 | `$ea48` | `CLR HTR2` |
| 169 | `$ea51` | `OVERTMP1` |
| 170 | `$ea5a` | `UNDRTMP1` |
| 171 | `$ea63` | `OVERTMP2` |
| 172 | `$ea6c` | `UNDRTMP2` |
| 173 | `$ea75` | `RGN OTMP` |
| 174 | `$ea7e` | `RGN UTMP` |
| 175 | `$ea87` | `DEW ALRM` |
| 176 | `$ea90` | `LBEDNOTE` |
| 177 | `$ea99` | `RBEDNOTE` |
| 178 | `$eaa2` | `RFLTRTMP` |
| 179 | `$eaab` | `RGN SEAL` |
| 180 | `$eab4` | `PROCFLTR` |
| 181 | `$eabd` | `RGN FLTR` |
| 182 | `$eac6` | `DEW SNSR` |
| 183 | `$eacf` | `HOP1 LOW` |
| 184 | `$ead8` | `HOP2 LOW` |
| 185 | `$eae1` | `CLOCKERR` |
| 186 | `$eaea` | `PROCBRNR` |
| 187 | `$eaf3` | `RGN BRNR` |
| 188 | `$eafc` | `P1 PROT ` |
| 189 | `$eb05` | `RGN PROT` |
| 190 | `$eb0e` | `CUST ALM` |
| 191 | `$eb17` | `CONLIFE1` |
| 192 | `$eb20` | `CONLIFE2` |
