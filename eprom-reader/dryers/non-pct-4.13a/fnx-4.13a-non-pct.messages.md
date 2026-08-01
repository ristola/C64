# Display message table: FNX 4.13A NON-PCT.bin

One continuous table, base `$DFAC`, 9 bytes/entry (8-char field + `$00`
terminator), 191 entries (index 0-190), spanning `$DFAC`-`$E662`. Same
9-byte-stride structure as dryer-fnx-4.20-pct.bin's $E460 table, at a
different base address and with 2 fewer entries - located independently for
this build (not the same table, not copied from the PCT dump) by searching
for known UI strings (`SETPOINT`, `DEWPOINT`) and confirming the surrounding
9-byte stride, then scanning outward to find the table's real start/end.

Not yet cross-referenced against actual lookup call sites in the code the
way the PCT table was (see dryer-fnx-4.20-pct.messages.md for that level of
detail) - this is the raw extracted catalog only.

| Index | Addr | Text |
|---|---|---|
| 0 | `$dfac` | `        ` |
| 1 | `$dfb5` | `OFF     ` |
| 2 | `$dfbe` | `  SURE? ` |
| 3 | `$dfc7` | `  N/A   ` |
| 4 | `$dfd0` | `MIN=    ` |
| 5 | `$dfd9` | `MAX=    ` |
| 6 | `$dfe2` | `SP1=    ` |
| 7 | `$dfeb` | `SP2=    ` |
| 8 | `$dff4` | `MS1=    ` |
| 9 | `$dffd` | `FUNC 000` |
| 10 | `$e006` | `NO FUNC ` |
| 11 | `$e00f` | `#T1=    ` |
| 12 | `$e018` | `#T2=    ` |
| 13 | `$e021` | `DPT= -  ` |
| 14 | `$e02a` | `DPX=    ` |
| 15 | `$e033` | `=       ` |
| 16 | `$e03c` | ` =      ` |
| 17 | `$e045` | `DAY=    ` |
| 18 | `$e04e` | `HOUR=   ` |
| 19 | `$e057` | `MIN=    ` |
| 20 | `$e060` | `MSSP=   ` |
| 21 | `$e069` | `MS=     ` |
| 22 | `$e072` | `INVAL MS` |
| 23 | `$e07b` | `INVAL PW` |
| 24 | `$e084` | `PW= ----` |
| 25 | `$e08d` | `PWLVL=  ` |
| 26 | `$e096` | `NEW ----` |
| 27 | `$e09f` | `VFY ----` |
| 28 | `$e0a8` | `PW CHNG ` |
| 29 | `$e0b1` | `NO MATCH` |
| 30 | `$e0ba` | `RESTART ` |
| 31 | `$e0c3` | `QUIKSTRT` |
| 32 | `$e0cc` | `HRS=    ` |
| 33 | `$e0d5` | `CHNG    ` |
| 34 | `$e0de` | `FATL=   ` |
| 35 | `$e0e7` | `OUTP=   ` |
| 36 | `$e0f0` | `LED=    ` |
| 37 | `$e0f9` | `NOALARMS` |
| 38 | `$e102` | `END ALMS` |
| 39 | `$e10b` | `FNX DHD ` |
| 40 | `$e114` | `VER ####` |
| 41 | `$e11d` | `1 PROCHT` |
| 42 | `$e126` | `2 PROCHT` |
| 43 | `$e12f` | `STD DEW ` |
| 44 | `$e138` | `KAHN DEW` |
| 45 | `$e141` | `TRANSMET` |
| 46 | `$e14a` | `````````` |
| 47 | `$e153` | `**WAIT**` |
| 48 | `$e15c` | `HZ=     ` |
| 49 | `$e165` | `TEST    ` |
| 50 | `$e16e` | `CE=     ` |
| 51 | `$e177` | `DE=     ` |
| 52 | `$e180` | `IC=     ` |
| 53 | `$e189` | `PC=     ` |
| 54 | `$e192` | `DC=     ` |
| 55 | `$e19b` | `T=      ` |
| 56 | `$e1a4` | `#T=     ` |
| 57 | `$e1ad` | `PARM=   ` |
| 58 | `$e1b6` | `DELETE? ` |
| 59 | `$e1bf` | `END CMDS` |
| 60 | `$e1c8` | `NO CMDS ` |
| 61 | `$e1d1` | `DELETED ` |
| 62 | `$e1da` | `MAX CMDS` |
| 63 | `$e1e3` | `CMD=    ` |
| 64 | `$e1ec` | `DEW=    ` |
| 65 | `$e1f5` | `ADD1=   ` |
| 66 | `$e1fe` | `ADD2=   ` |
| 67 | `$e207` | `BD=     ` |
| 68 | `$e210` | `PRG=    ` |
| 69 | `$e219` | `SEC=    ` |
| 70 | `$e222` | `GAS PROC` |
| 71 | `$e22b` | `ELECPROC` |
| 72 | `$e234` | `GAS RGN ` |
| 73 | `$e23d` | `ELEC RGN` |
| 74 | `$e246` | `SPI COMM` |
| 75 | `$e24f` | ` UD NET ` |
| 76 | `$e258` | `COOL    ` |
| 77 | `$e261` | `PCNT=   ` |
| 78 | `$e26a` | `OKST=   ` |
| 79 | `$e273` | `STD=    ` |
| 80 | `$e27c` | `    TEMP` |
| 81 | `$e285` | `     DEW` |
| 82 | `$e28e` | `ALARM ##` |
| 83 | `$e297` | `SETPOINT` |
| 84 | `$e2a0` | `STARTUP ` |
| 85 | `$e2a9` | `SHUTDOWN` |
| 86 | `$e2b2` | `MORE -1-` |
| 87 | `$e2bb` | `MAT SAVR` |
| 88 | `$e2c4` | `MS1RESET` |
| 89 | `$e2cd` | `MS2RESET` |
| 90 | `$e2d6` | `MS1SETUP` |
| 91 | `$e2df` | `MS2SETUP` |
| 92 | `$e2e8` | `BATCHCMD` |
| 93 | `$e2f1` | `VIEW CLK` |
| 94 | `$e2fa` | `SETCLOCK` |
| 95 | `$e303` | `VIEWCMDS` |
| 96 | `$e30c` | `NEW CMD ` |
| 97 | `$e315` | `PERM E/D` |
| 98 | `$e31e` | `DEL CMD ` |
| 99 | `$e327` | `DEL ALL ` |
| 100 | `$e330` | `#OVERTMP` |
| 101 | `$e339` | `DEW TRIG` |
| 102 | `$e342` | `DEW XTND` |
| 103 | `$e34b` | `MORE -2-` |
| 104 | `$e354` | ` ALARMS ` |
| 105 | `$e35d` | `PASSWORD` |
| 106 | `$e366` | `PW LEVEL` |
| 107 | `$e36f` | ` SET PW ` |
| 108 | `$e378` | ` CONFIG ` |
| 109 | `$e381` | `DEG F/C ` |
| 110 | `$e38a` | `QUIKTIME` |
| 111 | `$e393` | `COOLDOWN` |
| 112 | `$e39c` | `  SPI   ` |
| 113 | `$e3a5` | `ADDRESS ` |
| 114 | `$e3ae` | `  BAUD  ` |
| 115 | `$e3b7` | ` MAX SP ` |
| 116 | `$e3c0` | `RSTRDEFS` |
| 117 | `$e3c9` | `  SQC   ` |
| 118 | `$e3d2` | ` P1 AVG ` |
| 119 | `$e3db` | `P1 STDDV` |
| 120 | `$e3e4` | ` P2 AVG ` |
| 121 | `$e3ed` | `P2 STDDV` |
| 122 | `$e3f6` | ` DP AVG ` |
| 123 | `$e3ff` | `DP STDDV` |
| 124 | `$e408` | `RESETSQC` |
| 125 | `$e411` | `DIAGNOSE` |
| 126 | `$e41a` | `UNIT ID ` |
| 127 | `$e423` | `LAMPTEST` |
| 128 | `$e42c` | ` TEMPS  ` |
| 129 | `$e435` | `PROCESS1` |
| 130 | `$e43e` | `RETURN 1` |
| 131 | `$e447` | `REGENHTR` |
| 132 | `$e450` | `REGENOUT` |
| 133 | `$e459` | `PROCESS2` |
| 134 | `$e462` | `RETURN 2` |
| 135 | `$e46b` | `DEWPOINT` |
| 136 | `$e474` | `COMMDIAG` |
| 137 | `$e47d` | `ADV CAM ` |
| 138 | `$e486` | `OUTPUTS ` |
| 139 | `$e48f` | `PROCBLWR` |
| 140 | `$e498` | `REGNBLWR` |
| 141 | `$e4a1` | `VALVE 1 ` |
| 142 | `$e4aa` | `VALVE 2 ` |
| 143 | `$e4b3` | `GASONOFF` |
| 144 | `$e4bc` | `PROC1HTR` |
| 145 | `$e4c5` | `PROC2HTR` |
| 146 | `$e4ce` | `COOLCOIL` |
| 147 | `$e4d7` | `ALARMOUT` |
| 148 | `$e4e0` | `SERVICE ` |
| 149 | `$e4e9` | `NUM HTRS` |
| 150 | `$e4f2` | `HITURNDN` |
| 151 | `$e4fb` | `GASPURGE` |
| 152 | `$e504` | `CALIBRAT` |
| 153 | `$e50d` | `AC INPUT` |
| 154 | `$e516` | `DEW TYPE` |
| 155 | `$e51f` | `HOPR LVL` |
| 156 | `$e528` | `PROCFLTR` |
| 157 | `$e531` | `RGN FLTR` |
| 158 | `$e53a` | `  MISC  ` |
| 159 | `$e543` | ` P1 PID ` |
| 160 | `$e54c` | ` P2 PID ` |
| 161 | `$e555` | `PROC HTR` |
| 162 | `$e55e` | `P THRMST` |
| 163 | `$e567` | `R THRMST` |
| 164 | `$e570` | `ALARMLOG` |
| 165 | `$e579` | `CLEARLOG` |
| 166 | `$e582` | `VIEW LOG` |
| 167 | `$e58b` | `OVERTMP1` |
| 168 | `$e594` | `UNDRTMP1` |
| 169 | `$e59d` | `OVERTMP2` |
| 170 | `$e5a6` | `UNDRTMP2` |
| 171 | `$e5af` | `RGN OTMP` |
| 172 | `$e5b8` | `RGN UTMP` |
| 173 | `$e5c1` | `DEW ALRM` |
| 174 | `$e5ca` | `LBEDNOTE` |
| 175 | `$e5d3` | `RBEDNOTE` |
| 176 | `$e5dc` | `RFLTRTMP` |
| 177 | `$e5e5` | `RGN SEAL` |
| 178 | `$e5ee` | `PROCFLTR` |
| 179 | `$e5f7` | `RGN FLTR` |
| 180 | `$e600` | `DEW SNSR` |
| 181 | `$e609` | `HOP1 LOW` |
| 182 | `$e612` | `HOP2 LOW` |
| 183 | `$e61b` | `CLOCKERR` |
| 184 | `$e624` | `PROCBRNR` |
| 185 | `$e62d` | `RGN BRNR` |
| 186 | `$e636` | `P1 PROT ` |
| 187 | `$e63f` | `RGN PROT` |
| 188 | `$e648` | `CUST ALM` |
| 189 | `$e651` | `DEBUG 1 ` |
| 190 | `$e65a` | `DEBUG 2 ` |
