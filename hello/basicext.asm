; BASIC extension commands: CLS and HEX, added as real new BASIC
; keywords (typed and LISTed like any built-in command), not just
; SYS-callable routines. Cart-build only - included from hello_cart.asm,
; not common.asm - since this is only meaningful once the cart hands
; control to a live, persistent BASIC session (see cart_start).
;
; This is the same mechanism Simons' BASIC and similar cartridges used:
; patch three of BASIC's own RAM vectors so it calls out to us instead
; of erroring on tokens it doesn't recognize -
;   $0304/5 ICRNCH - tokenizer: recognize new keywords while crunching
;                    a typed line into tokens
;   $0306/7 IQPLOP - LIST: turn our tokens back into text
;   $0308/9 IGONE  - execute: dispatch our tokens when a line runs
; Falling through to the original stock routine for anything that
; ISN'T one of ours is what keeps normal BASIC (REM, DATA, quoted
; strings, all the existing keywords, ...) working exactly as before -
; get that wrong and every BASIC program on the machine breaks, not
; just ours.
;
; The tokenizer/detokenizer routines below (ConvertToTokens,
; ConvertFromTokens) are ported closely from a verified, working
; reference implementation (github.com/barryw/CustomBasicCommands)
; rather than reconstructed from scratch - this is effectively BASIC's
; own CRUNCH/LIST logic (REM/DATA/quote handling and all), extended to
; also check our own keyword table, and reproducing that faithfully is
; far safer than re-deriving its edge cases by hand.

; --- BASIC's own zero page, used here exactly as BASIC itself uses it
; (not our scratch - these are real, live BASIC interpreter state) ---
BAS_ENDCHAR = $08
BAS_COUNT   = $0b
BAS_VALTYP  = $0d
BAS_GARBFL  = $0f
BAS_FORPNT  = $49
BAS_FBUFPT  = $71
BAS_CHRGET  = $73        ; JSR: get next char, advance TXTPTR
BAS_CHRGOT  = $79        ; JSR: re-get current char, don't advance
BAS_TXTPTR  = $7a

; --- fixed BASIC ROM entry points ---
BAS_RESLST   = $a09e     ; stock keyword table (for the tokenizer)
BAS_NEWSTT   = $a7ae     ; resume BASIC's statement loop after a command
BAS_EXECOLD  = $a7ed     ; hand a not-ours token back to stock execution
BAS_FRMNUM   = $ad8a     ; evaluate + require a numeric expression
BAS_GETADR   = $b7f7     ; convert FAC1 to a 16-bit int in $14/$15

; --- fixed BASIC token values / addresses used by the tokenizer port ---
BTOK_DATA = $83
BTOK_REM  = $8f
BTOK_PRINT= $99
CHR_QUOTE = $22
LINE_BUF  = $0200        ; where BASIC assembles a typed line before crunching

; --- our new tokens: $CC upward, same free range Simons' BASIC etc.
; used (stock BASIC V2 never assigns tokens past the low $Cx area) ---
CMDSTART = $cc
CMDEND   = $cd           ; CLS=$cc, HEX=$cd

install_basic_ext
        lda     #<ConvertToTokens
        sta     $0304
        lda     #>ConvertToTokens
        sta     $0305
        lda     #<ConvertFromTokens
        sta     $0306
        lda     #>ConvertFromTokens
        sta     $0307
        lda     #<ExecuteCommand
        sta     $0308
        lda     #>ExecuteCommand
        sta     $0309
        rts

; --- Execute: BASIC's statement loop lands here (via the IGONE vector)
; whenever it meets a token it doesn't recognize itself. CHRGET fetches
; that token; if it's in our range, dispatch through CmdTab using the
; classic "push address-1, then jump into CHRGET" trick - CHRGET's own
; RTS lands exactly on the handler, and the handler's own RTS then pops
; the return address this JSR TestCmd pushed, landing back on
; "jmp BAS_NEWSTT" to resume BASIC. Anything outside our range re-fetches
; the token (CHRGOT, since CHRGET already consumed it) and falls
; through to the real BASIC dispatcher unchanged. ---
ExecuteCommand
        jsr     BAS_CHRGET
        jsr     TestCmd
        jmp     BAS_NEWSTT
TestCmd
        cmp     #CMDSTART
        bcc     OldCmd
        cmp     #CMDEND+1
        bcc     OkNew
OldCmd
        jsr     BAS_CHRGOT
        jmp     BAS_EXECOLD
OkNew
        sec
        sbc     #CMDSTART
        asl
        tax
        lda     CmdTab+1,x
        pha
        lda     CmdTab,x
        pha
        jmp     BAS_CHRGET

CmdTab
        !word   ClsCmd-1
        !word   HexCmd-1

; --- CLS: clear the screen. As simple as a new command gets. ---
ClsCmd
        lda     #$93
        jmp     $ffd2

; --- HEX <expr>: print a 16-bit value as 4 hex digits, e.g. HEX 255
; prints $00FF. A command, not a HEX$() expression function - see the
; file-level comment on why this stops short of returning a string. ---
HexCmd
        jsr     hex_get16
        lda     #$24        ; '$' prefix
        jsr     $ffd2
        lda     $15
        jsr     print_hex
        lda     $14
        jsr     print_hex
        rts

hex_get16
        lda     #$00
        sta     BAS_VALTYP
        jsr     BAS_FRMNUM
        jsr     BAS_GETADR
        rts

; --- Tokenize: BASIC's line-crunch calls here (via ICRNCH) for each
; word in a freshly-typed line. Tries the stock keyword table
; (BAS_RESLST) first so every existing BASIC keyword still works
; exactly as before, then falls through to NewTab for ours. ---
ConvertToTokens
        ldx     BAS_TXTPTR
        ldy     #4
        sty     BAS_GARBFL
NextChar
        lda     LINE_BUF,x
        bpl     Normal
        cmp     #$ff
        beq     TakChar
        inx
        bne     NextChar
Normal
        cmp     #' '
        beq     TakChar
        sta     BAS_ENDCHAR
        cmp     #CHR_QUOTE
        beq     GetChar
        bit     BAS_GARBFL
        bvs     TakChar
        cmp     #'?'
        bne     Skip
        lda     #BTOK_PRINT
        bne     TakChar
Skip
        cmp     #'0'
        bcc     Skip1
        cmp     #'<'
        bcc     TakChar
Skip1
        sty     BAS_FBUFPT
        ldy     #0
        sty     BAS_COUNT
        dey
        stx     BAS_TXTPTR
        dex
CmpLoop
        iny
        inx
TestNext
        lda     LINE_BUF,x
        sec
        sbc     BAS_RESLST,y
        beq     CmpLoop
        cmp     #$80
        bne     NextCmd
        ora     BAS_COUNT
TakChar1
        ldy     BAS_FBUFPT
TakChar
        inx
        iny
        sta     LINE_BUF-5,y
        cmp     #0
        beq     End
        sec
        sbc     #':'
        beq     Skip2
        cmp     #BTOK_DATA-':'
        bne     Skip3
Skip2
        sta     BAS_GARBFL
Skip3
        sec
        sbc     #BTOK_REM-':'
        bne     NextChar
        sta     BAS_ENDCHAR
RemLoop
        lda     LINE_BUF,x
        beq     TakChar
        cmp     BAS_ENDCHAR
        beq     TakChar
GetChar
        iny
        sta     LINE_BUF-5,y
        inx
        bne     RemLoop
NextCmd
        ldx     BAS_TXTPTR
        inc     BAS_COUNT
Continue
        iny
        lda     BAS_RESLST-1,y
        bpl     Continue
        lda     BAS_RESLST,y
        bne     TestNext
        beq     NewTok
NotFound
        lda     LINE_BUF,x
        bpl     TakChar1
End
        sta     LINE_BUF-3,y
        dec     BAS_TXTPTR+1
        lda     #$ff
        sta     BAS_TXTPTR
        rts
NewTok
        ldy     #0
        lda     NewTab,y
        bne     NewTest
NewCmp
        iny
        inx
NewTest
        lda     LINE_BUF,x
        sec
        sbc     NewTab,y
        beq     NewCmp
        cmp     #$80
        bne     NextNew
        ora     BAS_COUNT
        bne     TakChar1
NextNew
        ldx     BAS_TXTPTR
        inc     BAS_COUNT
Cont1
        iny
        lda     NewTab-1,y
        bpl     Cont1
        lda     NewTab,y
        bne     NewTest
        beq     NotFound

; --- Detokenize: BASIC's LIST calls here (via IQPLOP) for every byte
; with the high bit set. $A724/$A6F3/$A6EF are fixed reentry points
; inside BASIC's own LIST routine (verified against the reference
; implementation, not guessed). ---
ConvertFromTokens
        bpl     ListOut
        bit     BAS_GARBFL
        bmi     ListOut
        cmp     #$ff
        beq     ListOut
        cmp     #CMDSTART
        bcs     NewList
        jmp     $a724
ListOut
        jmp     $a6f3
NewList
        sec
        sbc     #$cb
        tax
        sty     BAS_FORPNT
        ldy     #$ff
ListNext
        dex
        beq     ListFound
ListLoop
        iny
        lda     NewTab,y
        bpl     ListLoop
        bmi     ListNext
ListFound
        iny
        lda     NewTab,y
        bmi     ListOldEnd
        jsr     $ab47       ; basic.CHAROUT
        bne     ListFound
ListOldEnd
        jmp     $a6ef

; Keyword table for both the tokenizer and detokenizer above - the
; last character of each name has $80 added to mark the end. Order
; must match CmdTab, and token values are assigned sequentially from
; CMDSTART (so CLS=$cc, HEX=$cd).
NewTab
        !text   "CL"
        !byte   'S'+$80
        !text   "HE"
        !byte   'X'+$80
        !byte   0
