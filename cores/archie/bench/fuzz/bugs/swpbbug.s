	AREA    |main|, CODE, READONLY
        EXPORT  _start

	ORG	&1000
_start
	TEQP	PC,#3
	ADR	R14,datatable
	SWPB	R1,R9,[R14]
EXIT	
	NOP	
	NOP	
	
	SWI	&FFFFFF

	NOP
	NOP
		
datatable
	&	&12345678
	&	&00000000
	&	&00000000
	&	&00000001
	&	&000010b8
	&	&0004b000
	&	&00000000
	&	&00000000
	&	&00001064
	&	&00050000
	&	&0381a290
	&	&0026dc06
	&	&00001000
	&	&01c01eb4
	

	END
