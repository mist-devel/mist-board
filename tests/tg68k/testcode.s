	org $fc0000		;

start:
;	jsr	sub
	move    #$a700,sr             ; Enter trace mode
;        nop			      ;
	lsr	#5,d0
	
;       move.l  #$3237,d0
;	pack    d0,d5,#$0123   		; d5 = $3a
;	unpk    d5,d6,#$4040    	; d6 = $434a
;	move.l  #testdata1,a0
;	move.l  #testdata2,a1
;	pack    -(a0),-(a1),#$1122
;	pack    -(a0),-(a1),#$f0f0
;	unpk    -(a0),-(a1),#$1122
;	unpk    -(a0),-(a1),#$f0f0
loop:	move    d0,d0
	bra.s   loop

sub:	rts
	
	dc.l    0,0,0,0

	dc.l    $12345678
testdata1:
	dc.l    $aaaaaaaa
	
	dc.l    $c0ffee12
testdata2:
        dc.l    $55555555	

	org $fc0100			; 
trace:	rte
	
