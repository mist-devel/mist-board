	;; 68020 mulu.l
	;; http://atari-forum.com/viewtopic.php?f=117&t=32761&start=925#p383381

;	move.l  #$a26b,d0
;	move.l  #$7667,d1
;	mulu.w  d1,d0		; 4B1EAB0D
;	move.l  d0,testword1  	; to see value being written
	
	move.l  #$a26bd7e0,d0
	move.l  #$7667c08f,d1
;	mulu.l  d0,d1
	mulu.l  d0,d1:d2
	move.l  d1,testword1  	; to see value being written
	move.l  d2,testword1  	; to see value being written
	cmp.l   #$b7459620,d1	; 4B1F8910 B7459620
	bne	fail

	move.l  #$a26bd7e0,d0
	move.l  #$7667c08f,d1
	mulu.l  d1,d0
	move.l  d0,testword1  	; to see value being written
	cmp.l   #$b7459620,d0   ; 4B1F8910 B7459620
	bne	fail
