	;; 68020 pack/unpk
	; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/pack.HTML
	; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/unpk.HTML
	
	move.l  #$3237,d0
        pack    d0,d5,#$0123            ; d5 = $3a
	cmp	#$3a,d5
	bne	fail
        unpk    d5,d6,#$4040            ; d6 = $434a
	cmp	#$434a,d6
	bne	fail

	move.l  #testword3+2,a0
	move.l  #testword4+1,a1	
	move.w	#$1234,testword3        ; test word
        pack    -(a0),-(a1),#$1122
	
	cmp.b	#$36,testword4
	bne	fail
	
	move.l  #testword4+1,a0
	move.l  #testword3+2,a1
	unpk    -(a0),-(a1),#$1122

	cmp	#$1428,testword3
	bne     fail
