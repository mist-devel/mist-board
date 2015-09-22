	;; 64k ram are at $10000
	dc.l   $10400		; some stack
	dc.l   start

testword3 equ $10100
testword4 equ $10104
	
start:
;	include	"tests/cmpi_d16_pc.s"
	include	"tests/bfxxx.s"
;	include	"tests/bcd.s"

	;; if all tests pass the code will arrive here
	move.b	#0,$beefed	; exit with result 0
loop:	bra   	loop

	;; if a test fails the code will jump here
fail:	move.b	#1,$beefed	; exit with result 1
loopf:	bra   	loopf

testword1:	dc.l $10000
testword2:	dc.l $10004

