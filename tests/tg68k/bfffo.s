        ;; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/bfffo.HTML
        ;; http://68k.hax.com/BFFFO

	dc.l   0
        dc.l   start

test:	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	dc.l	@l
	
start:
	move		#@w<0,6>,d0
	
	move		#@b,ccr
	bfffo		test+@b<0,3>{d0:@b<1,32>},d4
	move		ccr,$c0ffee42+64

	move.l		#@l,d3
	move		#@b,ccr
	bfffo		d3{d0:@b<1,32>},d5
	move		ccr,$c0ffee42+64

	move.l		test,d0
	move.l		test+4,d1
	move.l		test+8,d2

	;; the following will write the register contents to stdout which will
	;; then be used for the comparison
	move.l		d0,$c0ffee42
	move.l		d1,$c0ffee42+4
	move.l		d2,$c0ffee42+8
	move.l		d3,$c0ffee42+12
	move.l		d4,$c0ffee42+16
	move.l		d5,$c0ffee42+20

	move.b		#0,$beefed
