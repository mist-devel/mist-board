	dc.l   0
        dc.l   start

test:	dc.l	@l
	dc.l	@l
	dc.l	@l
	
start:
	move.l		#@l,d0
	
	move		#@b,ccr
	bfchg		test+@b<0,3>{@b<0,31>:@b<1,32>}
	move		ccr,$c0ffee42+64

	move.l		#@l,d3
	move		#@b,ccr
	bfchg		d3{@b<0,31>:@b<1,32>}
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

	move.b		#0,$beefed
