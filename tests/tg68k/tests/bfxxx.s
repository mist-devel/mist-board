	;; tests of the bitfield instructions
	; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/bfset.HTML
	; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/bfchg.HTML
	; http://oldwww.nvg.ntnu.no/amiga/MC680x0_Sections/bfclr.HTML

	;; test register wrapping
	;; this test failed in tg68 since the target register always
	;; was d0
	move.l  #$11223344,d2
	bfset	d2{24:16}
	bmi	fail			; msb ($44) was not set
	cmp.l 	#$ff2233ff,d2
	bne	fail

	;; test writing over 32 bit boundaries. This failed on Musashi since
	;; it didn't properly write the fifth byte. Tg68k failed the test for
	;; the z bit since flags didn't work at all
	move.l  #$abc00000,testword1
	move.l  #$00067bcd,testword1+4
	bfset	testword1{12:32}
	bne 	fail			; bits were all 0 before
	bmi	fail			; msb was not set
	cmp.l 	#$abcfffff,testword1
   	bne     fail
  	cmp.l 	#$fff67bcd,testword1+4
 	bne     fail

 	move.l  #$a0010bcd,testword1
 	bfset	testword1{4:16}
 	beq	fail			; one bit wasn't 0
	bmi	fail			; msb was not set

 	move.l  #$a8000bcd,testword1
 	bfset	testword1{4:16}
 	beq	fail			; one bit wasn't 0
	bpl	fail			; msb was set

	;; bftst
 	move.l  #$a0000bcd,testword3
  	bftst	testword3{4:16}
 	bne	fail			; bits were all 0 before
	bmi	fail			; msb was not set

	;; bftst 1 bit in 5th byte read
 	move.l  #$a0000000,testword3
 	move.l  #$40000000,testword3+4
  	bftst	testword3{4:32}
 	beq	fail			; bit 30 was 1
	bmi	fail			; msb was not set

	;; bfclr
 	move.l  #$01234567,testword3
 	move.l  #$89abcdef,testword3+4
  	bfclr	testword3{4:32}
 	beq	fail			; many bits were set
	bmi	fail			; msb was not set
  	cmp.l 	#$00000000,testword3
 	bne     fail
  	cmp.l 	#$09abcdef,testword3+4
 	bne     fail

	;; bfchg
 	move.l  #$01234567,testword3
 	move.l  #$89abcdef,testword3+4
  	bfchg	testword3{4:32}
 	beq	fail			; many bits were set
	bmi	fail			; msb was not set
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
 	move.l  #$f000ffff,testword3
	bfffo	testword3{4:16},d4
	cmp	#16,d4
	bne	fail

 	move.l  #$12345678,testword3
	bfffo	testword3{20:10},d6
	cmp	#21,d6
	bne	fail
	
	;; test some of the 68020 addressing modes
	move.l  #$12345678,testword3
 	move.l  #$89abcdef,testword3+4
 	move.l  #$11223344,testword3+8
 	move.l  #$8899aabb,testword3+12
	move.l  #testword3,a3
	move.l	#1,d2
	bfset	(4,a3,d2*4){10:32}
	cmp.l	#$113fffff,testword3+8
	bne	fail
	cmp.l	#$ffd9aabb,testword3+12
	bne	fail
	
