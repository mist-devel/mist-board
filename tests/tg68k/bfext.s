        ;; 64k ram are at $10000
	;; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/bfexts.HTML
	;; http://68k.hax.com/BFESTS
        dc.l   $10400           ; some stack
        dc.l   start

	dc.l	@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l
	dc.l	@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l
	dc.l	@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l,@l
test:	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	
start:
	move		#@b,ccr

	move.l		#@l<0,127>-64,d0
	move.l		#@l,d1
	move.l		#$ffffffff,d3
	move.w		#@w<0,3>,d3
	move.w		#@w,d4
	move.l		#test,a5
	
	bfextu          (a5,d3.w*2){d0:@b<1,32>},d6
	move		ccr,$c0ffee42+64
	bfextu          (a5,d3.w*2){d0:d4},d5
	bfexts          (a5,d3.w*2){d0:d4},d7
	bfexts          d1{d0:d4},d4

	move		ccr,$c0ffee42+64
	
	move.l		d0,$c0ffee42
	move.l		d3,$c0ffee42+12
	move.l		d4,$c0ffee42+16
	move.l		d5,$c0ffee42+20
	move.l		d6,$c0ffee42+24
	move.l		d7,$c0ffee42+28
	move.l		a5,$c0ffee42+32+20

	move.b		#0,$beefed
