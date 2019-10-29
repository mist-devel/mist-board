	;; 68020 mulu.l
	;; http://atari-forum.com/viewtopic.php?f=117&t=32761&start=925#p383381

	move.l  #$a26b,d0
	move.l  #$7667,d1
	mulu.w  d1,d0		; 4B1EAB0D
	move.l  d0,testword1  	; to see value being written
        cmp.l   #$4B1EAB0D,d0
	bne	fail
	
;	move.l  #$a26bd7e0,d0
;	move.l  #$7667c08f,d1
;	mulu.l  d0,d1
	
	move.l  #$a26bd7e0,d0
	move.l  #$7667c08f,d1
	mulu.l  d0,d2:d1
	move.l  d1,testword1
	move.l  d2,testword1
	cmp.l   #$4B1F8910,d2	; 4B1F8910 B7459620
	bne	fail
	cmp.l   #$b7459620,d1
	bne	fail

	move.l  #$ffff0000,d4
	mulu.l  d4,d1:d4
	move.w  ccr,testword1
	move.l  d4,testword1
	move.l  d1,testword1
	cmp.l   #$00000000,d4	; fffe0001 00000000
	bne	fail
	cmp.l   #$fffe0001,d1
	bne	fail

	move.l  #$a26bd7e0,d0
	move.l  #$7667c08f,d1
	mulu.l  d0,d1
	move.l  d1,testword1
	cmp.l   #$b7459620,d1
	bne	fail

	move.l  #$a26bd7e0,d0
	move.l  #$7667c08f,d1
	mulu.l  d1,d0
	move.l  d0,testword1
	cmp.l   #$b7459620,d0   ; 4B1F8910 B7459620
	bne	fail
