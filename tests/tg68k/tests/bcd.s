	;; bcd tests
	;; http://tict.ticalc.org/docs/68kguide.txt
	;; TODO: test addressing modes
	
	clr.l	d0		; at startup hw registers are undefined
	clr.l	d1		; and arithmetic will fail in ghdl
	
	move	#$66,d0
	move	#$14,d1
	andi	#$ef,ccr	; clear x bit
	abcd	d1,d0		; 66+14=80
	bcs	fail 		; carry should not be set
	cmp	#$80,d0
	bne	fail

	move	#$32,d0
	move	#$19,d1
	ori	#$10,ccr	; set x bit
	abcd	d1,d0		; 32+19+1=52
	bcs	fail 		; carry should not be set
	cmp	#$52,d0
	bne	fail

	move	#$81,d0
	move	#$32,d1
	andi	#$ef,ccr	; clear x bit
	abcd	d1,d0		; 81+32=113
	bcc	fail 		; carry should be set
	cmp	#$13,d0
	bne	fail

	move	#$81,d0
	move	#$32,d1
	andi	#$ef,ccr	; clear x bit
	sbcd	d1,d0		; 81-32=49
	bcs	fail 		; carry should not be set
	cmp	#$49,d0
	bne	fail

	move	#$32,d0
	move	#$81,d1
	andi	#$ef,ccr	; clear x bit
	sbcd	d1,d0		; 32-81=-49 (->100-51)
	bcc	fail 		; carry should be set
	cmp	#$51,d0
	bne	fail

	move	#$19,d0
	move	#$42,d1
	ori	#$10,ccr	; set x bit
	sbcd	d1,d0		; 19-42-1=-24 (->100-76)
	bcc	fail 		; carry should be set
	cmp	#$76,d0
	bne	fail

	move	#$33,d0
	move	#$33,d1
	andi	#$fb,ccr	; clear z bit
	andi	#$ef,ccr	; clear x bit
	sbcd	d1,d0		; 33-33=0
	beq	fail		; z flag should still not be set

	move	#$42,d0
	move	#$42,d1
	ori	#$04,ccr	; set z bit
	andi	#$ef,ccr	; clear x bit
	sbcd	d1,d0		; 42-42=0
	bne	fail		; z flag should be set

	move	#$19,d1
	andi	#$ef,ccr	; clear x bit
	nbcd	d1		; 100-19=81
	bcc	fail 		; carry should be set
	beq	fail		; z flag should not be set
	cmp	#$81,d1
	bne	fail

	move	#$22,d1
	ori	#$10,ccr	; set x bit
	nbcd	d1		; 100-22-1=77
	bcc	fail 		; carry should be set
	cmp	#$77,d1
	bne	fail

	move	#$99,d1
	ori	#$10,ccr	; set x bit
	ori	#$04,ccr	; set z bit
	nbcd	d1		; 100-99-1=0
	bcc	fail 		; carry should be set
	bne	fail		; z flag should be set
	cmp	#$00,d1
	bne	fail

	; 	move.l	d1,testword1	
