	;; Atari ST tos test template

	move.l  #msg,-(sp)              ; 
        move.w  #9,-(sp)                ; CConws
        trap    #1                      ; gemdos
        addq.l  #6,sp

	include "test.s"

	move.l  #okmsg,-(sp)         ; 
        move.w  #9,-(sp)                ; CConws
        trap    #1                      ; gemdos
        addq.l  #6,sp

exit:	
        move.w  #1,-(sp)                ; CConin
        trap    #1                      ; gemdos
        addq.l  #2,sp                   ; Correct stack

        move.w  #0,-(sp)                ; Pterm0
        trap    #1                      ; gemdos
        addq.l  #2,sp                   ; Correct stack
	rts

fail:	move.l  #failmsg,-(sp)         ; 
        move.w  #9,-(sp)                ; CConws
        trap    #1                      ; gemdos
        addq.l  #6,sp
	bra 	exit
	
failmsg:dc.b	"Test failed", 13,10,0
	even
okmsg:	dc.b	"Test ok", 13,10,0
	even
msg:	dc.b	"Executing test ...", 13,10,0
	even
	
	bss
testword3:	ds.l 1
testword4:	ds.l 1
		ds.l 16
	

