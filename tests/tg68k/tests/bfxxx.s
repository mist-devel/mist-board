	;; tests of the bitfield instructions

	;; test register wrapping
	;; this test failed in tg68 since the target register always
	;; was d0
	move.l  #$11223344,d2
	bfset	d2{24:16}
	cmp.l 	#$ff2233ff,d2
	bne	fail

	;; test writing over 32 bit boundaries. This failed on Musashi since
	;; it didn't properly write the fifth byte. Tg68k failed the test for
	;; the z bit since flags didn't work at all
	move.l  #$abc00000,testword1
	move.l  #$00067bcd,testword1+4
	bfset	testword1{12:32}
	bne 	fail			; bits were all 0 before
	cmp.l 	#$abcfffff,testword1
   	bne     fail
  	cmp.l 	#$fff67bcd,testword1+4
 	bne     fail

 	move.l  #$a0010bcd,testword1
 	bfset	testword1{4:16}
 	beq	fail			; one bit wasn't 0

	;; bftst
 	move.l  #$a0000bcd,testword3
  	bftst	testword3{4:16}
 	bne	fail			; bits were all 0 before

	;; bftst 1 bit in 5th byte read
 	move.l  #$a0000000,testword3
 	move.l  #$40000000,testword3+4
  	bftst	testword3{4:32}
 	beq	fail			; bit 30 was 1

	;; bfclr
 	move.l  #$01234567,testword3
 	move.l  #$89abcdef,testword3+4
  	bfclr	testword3{4:32}
 	beq	fail			; many bits were set
  	cmp.l 	#$00000000,testword3
 	bne     fail
  	cmp.l 	#$09abcdef,testword3+4
 	bne     fail

	;; bfchg
 	move.l  #$01234567,testword3
 	move.l  #$89abcdef,testword3+4
  	bfchg	testword3{4:32}
  	cmp.l 	#$0edcba98,testword3
 	bne     fail
  	cmp.l 	#$79abcdef,testword3+4
 	bne     fail

	;; bfextu/s
 	move.l  #$01234567,testword3
 	move.l  #$89abcdef,testword3+4
	bfextu  testword3{7:29},d0
  	cmp.l 	#$12345678,d0		; just the bits
	bfexts  testword3{7:29},d0
  	cmp.l 	#$f2345678,d0		; sign extended
	bne  	fail

	;; bfins
 	move.l  #$12345678,testword3
	move    #$affe,d4
	bfins	d4,testword3{4:16}
	beq	fail 			; inserted value is not 0
	cmp.l	#$1affe678,testword3
	bne	fail

	;; bfffo
	
