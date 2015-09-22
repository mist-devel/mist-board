	;; test for cmpi d16(pc) bug
	move.l  #$11223344,testword1
	cmp.l   #$11223344,testword1(PC)
	bne.s	fail
	
