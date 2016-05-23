	AREA    |main|, CODE, READONLY
        EXPORT  _start

	ORG	&1000
_start
	MOV	R2,#0
	ADR	R12,data1
	TEQ	R12,#0

	LDR     R3,[R12]
	ANDS    R2,R3,#&FF         ; ="\377"
	
	MOVNE   R1,R2
	MOVNE   R0,#&A1
	
EXIT	
	NOP	
	NOP	
	
	SWI	&FFFFFF

	NOP
	NOP

data1
	&	&001000b0		
	END
