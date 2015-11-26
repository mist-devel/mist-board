	;; This is a nasty hack. This overwrites the reti at 0x38 which has already
	;; been set by crt0.s with a jump into our interrupt routine. This results
	;; in two contradicting entries in the hex file and the converter has to deal
	;; with that. srec_cat can be told to accept it. Quartus accepts it by default
       	.globl	_isr
        .area   VECTOR (ABS)

	.org	0x38
	jp	_isr
