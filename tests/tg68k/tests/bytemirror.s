	;; byte mirror test

	move.b  #$a5,testword1	 ; $a5a5 has to show up on databus
	move.b  #$5a,testword1+1 ; $5a5a has to show up on databus
