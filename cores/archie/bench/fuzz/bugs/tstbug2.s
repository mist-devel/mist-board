	AREA    |main|, CODE, READONLY
        EXPORT  _start

	ORG	&1000
_start

	MOV	R0,#2
	MOV	R1,#1
	MOV	R3,#&930

	CMP     R0,#1
	MOV     R1,#0
	MOV     R1,R3
	TST     R1,#&10            ; =16
		
	MOVCS   R0,#1 ; Actual
	MOVCC   R0,#0 ; Expected

	NOP
	NOP
	
	SWI	&FFFFFF

	NOP
	NOP

	END
