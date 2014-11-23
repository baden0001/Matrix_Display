;***************************************************
;	Matrix_Display.asm
;***************************************************
;	Program is used for the Fairplay Matrix display
;	
;	20 MHz crystal = .000 000 05
;
;	HS operation
;
;	v2 		Stripped out 2nd display
;	v2.01	Added buffer and scroll capability
;			No known bugs
;			Program length is getting long enough that size limits 
;			 might be seen if it gets larger
;			Lookup table is located @ 0x600.  Program runs to past 0x200
;	v2.02	Changed letter organization to include all caps letters
;			 added numbers changed message.
;	v2.03	Changed display to "OMAHA MINI MAKER FAIRE 2014"
;	v2.04	Added Analog input speed adjust to AN0
;***************************************************
;	Notes:	
;
;		Timer2 sets the data rate for communications
;		 with the Matrix display
;
;		Timer2 = Interval Time/(Tosc*4*prescaler)
;		 = 0.0000096/(50 ns*4*1) = 48 = 0x30
;		 This value is placed into PR2 which acts
;		 as a comparator, once Timer2 = PR2
;		 Timer2 resets to zero
;		originally set to 0x30, now set to 0x70
;		 112 = x/(50 ns*4*1)
;		 x = 22.4 microS = 448 cycles 
;
;		Allows for 192 steps in a program between
;		 timer interrupts.
;
;		If Timer2 is setup for 4 prescale then:
;		 = .001/(250 ns*4*4) = 250 = 0xFA
;		Under this setup the exact count to within
;		 1/250th of a mS can be figured. (.004 of 
;		 1 mS)
;
;		TMR2 holds current count that is compared
;		 against PR2
;***************************************************
;	Data that is to be displayed will need to adhere to the following setup
;
;	The displays data will be 32 bytes long. Capable of displaying 8 rows 
;		4 bytes long. RowDatH, RowDatM, RowDatL, RowDatLL will hold the
;		current rows data where RowDatLL will be first on the table followed by
;		RowDatL etc. . .
;	Display Data
;	Byte			Data
;	0				RowDatLL			Eighth Row
;	1				RowDatL
;	2				RowDatM
;	3				RowDatH
;	4				RowDatLL etc. . . 	Seventh Row
;
;	DDRAMPos is used as the pointer that references the table
;
;Here is a breakdown of the Display
;	RowDatH		RowDatM		RowDatL		RowDatLL
;A	11111111	22222222	33333333	44444444	First Row
;B	11111111	22222222	33333333	44444444	Second Row
;C	11111111	22222222	33333333	44444444	Third Row
;D	11111111	22222222	33333333	44444444	Fourth Row
;E	11111111	22222222	33333333	44444444	Fifth Row
;F	11111111	22222222	33333333	44444444	Sixth Row
;G	11111111	22222222	33333333	44444444	Seventh Row
;H	11111111	22222222	33333333	44444444	Eighth Row
;
;	RowDatBuf
;A	55555555	First Row
;B	55555555	Second Row
;C	55555555	Third Row
;D	55555555	Fourth Row
;E	55555555	Fifth Row
;F	55555555	Sixth Row
;G	55555555	Seventh Row
;H	55555555	Eighth Row
;
;	Due to wanting two displays, there will be a second clock
;		Row2_Clock.  This will clock after Row_Clock has finished
;		RowDatH, RowDatM, RowDatL and RowDatLL will all be used
;		in the second display.  DDRAMPos2 will be the pointer for the
;		second displays table.
;
;***************************************************

	list p=16F870

	include "p16F870.inc"

	LIST
	__config _HS_OSC & _WDT_OFF & _LVP_OFF


	CBLOCK 0x20
	StatTemp, PCLTemp, WTemp, Col_Cnt, Row_Cnt, Col_Dat, MatrixSpeed, Temp
	Mat_Info, RowDatH, RowDatM, RowDatL, RowDatLL, DDRAMPos
	Timer, RowDatBuf
	RowDatHA, RowDatHB, RowDatHC, RowDatHD, RowDatHE, RowDatHF, RowDatHG, RowDatHH
	RowDatMA, RowDatMB, RowDatMC, RowDatMD, RowDatME, RowDatMF, RowDatMG, RowDatMH
	RowDatLA, RowDatLB, RowDatLC, RowDatLD, RowDatLE, RowDatLF, RowDatLG, RowDatLH
	RowDatLLA, RowDatLLB, RowDatLLC, RowDatLLD, RowDatLLE, RowDatLLF, RowDatLLG, RowDatLLH
	RowDatBufA, RowDatBufB, RowDatBufC, RowDatBufD, RowDatBufE, RowDatBufF, RowDatBufG, RowDatBufH
	LtrPnt, Inner, Outer, Delay2, HiPnt, LtrOfst
	ENDC

;***************************************************
;	Define Constants used in program
#define	Tmr2Lmt			0x70
#define Data_Line		0
#define Col_Clock		1
#define	Row_Clock		2
#define Row2_Clock		3
#define letA			D'0'
#define letB			D'9'
#define letC			D'18'
#define letD			D'27'
#define letE			D'36'
#define letF			D'45'
#define letG			D'54'
#define letH			D'63'
#define letI			D'72'
#define letJ			D'81'
#define letK			D'90'
#define letL			D'99'
#define letM			D'108'
#define letN			D'117'
#define letO			D'126'
#define letP			D'135'
#define letQ			D'144'
#define letR			D'153'
#define letS			D'162'
#define letT			D'171'
#define letU			D'180'
#define letV			D'189'
#define letW			D'198'
#define letX			D'207'
#define letY			D'216'
#define letZ			D'225'
#define num1			D'0'
#define num2			D'9'
#define num3			D'18'
#define num4			D'27'
#define num5			D'36'
#define num6			D'45'
#define num7			D'54'
#define num8			D'63'
#define num9			D'72'
#define symSpace		D'81'
#define symWEx			D'90'
#define symTEx			D'99'
#define symEq			D'108'

;***************************************************
;Controls:
;	PORTA,0				Potentiometer, (Input)
;	PORTC,0				Data (Data_Line)
;	PORTC,1				Columns Clock (Col_Clock) (Rows on Board)
;	PORTC,2				Rows Clock (Row_Clock) (Columns on Board)
;	PORTC,3				Rows2 Clock (Row2_Clock) (Columns on Board)
;
;Variables:
;	StatTemp, PCLTemp, WTemp	Temps used to save state info
;								 during Interrupts
;
;	Col_Cnt						Count used in outputting
;								 8 clock cycles for
;								 columns
;
;	Row_Cnt						Count used in outputting
;								 32 clock cycles for
;								 rows
;
;	Col_Dat						Keeps track of current column
;								 being output
;
;	RowDatH, RowDatM			Holds data for current Row
;	 RowDatL, RowDatLL			 being output
;
;	RowDatHA..HH				LeftMost Sector of Display
;	RowDatMA..MH				Second from left sector of display
;	RowDatLA..LH				Third from left sector of display
;	RowDatLLA..LLH				Fourth from left sector of display
;	RowDatBufA..BufH			Store whole letters in this section
;								 to be cycled into display
;	
;	Mat_Info					Holds information about the 
;								 communications process
;								Bit 0	=	'1' Need to cycle clock
;											'0' Need to cycle data
;								Bit 1	=	'1' Need to cycle Columns
;											'0' Need to cycle Rows
;								Bit 2	=	'1' Need to shift Column Data
;											'0' Column Data OK
;
;	Tmr2Lmt						Sets the Timer period
;
;	DDRAMPos					Holds next row of display address to be serviced
;								Bit 0	=	'A' Row
;								Bit 1	=	'B' Row
;								Bit 2	=	'C' Row
;								Bit 3	=	'D' Row
;								Bit 4	=	'E' Row
;								Bit 5	=	'F' Row
;								Bit 6	=	'G' Row
;								Bit 7	=	'H' Row
;
;	Timer						Used as a timer to alternate between messages
;
;	LtrPnt						Keeps track of where at in the letter we are in width
;					
;	Inner, Outer, Delay2		Used for main program timing
;
;	HiPnt						Pointer to select the high location of current letter
;								 being stored into buffer
;
;	LtrOfst						Holds offset to access letter that is being loaded
;								 into buffer.  This will help to shrink
;								 the size of the code
;
;	MatrixSpeed					Used to adjust speed of scrolling of display
;
;***************************************************

Reset_Vector	code 0x0000
 	goto	Start

Int_Vector		code 0x0004
	goto	IntService

	code 0x002A
;****************************************
;	Setup Capture, Timer and Input
;****************************************
Start
;Setup output Port
	bsf		STATUS,RP0		;Bank 1 select
	clrf	TRISC			;Set Port C up for outputs
	bcf		STATUS,RP0		;Bank 0 Select
	clrf	PORTC
	bsf		PORTC,Data_Line ;Set all outputs high
	bsf		PORTC,Col_Clock
	bsf		PORTC,Row_Clock

;Setup Timer2 and interrupt
;	movlw	B'00000010'		;1:16 Prescale, 1:1 Postscale, timer off
;	movlw	B'00000001'		;1:4  Prescale, 1:1 Postscale, timer off
	movlw	B'00000000'		;1:1  Prescale, 1:1 Postscale, timer off
	movwf	T2CON
	clrf	TMR2			;Reset Timer2 count
	bcf		PIR1,1			;Clear Timer2 Flag
	bsf		STATUS,RP0		;Bank 1 Select
	movlw	Tmr2Lmt			;Load Limit to Timer2
	movwf	PR2				; Calculated above
	bsf		PIE1,1			;Enable Timer2 Interrupt
	bcf		STATUS,RP0		;Bank 0 Select
	bsf		T2CON,2			;Turn Timer2 on

;Setup Variables
	movlw	B'00001000'		;load columns clock count
	movwf	Col_Cnt
	movlw	B'00100001'		;load rows clock count
	movwf	Row_Cnt
	movlw	B'00000001'		;Load column position
	movwf	Col_Dat
	bcf		Mat_Info,0		;Data needs to be serviced
	bsf		Mat_Info,1		;Set Columns to be cycled
	bcf		Mat_Info,2		;No Column Data shift needed

;Setup Analog input
	movlw	B'00001110'		;Left Justified
							; 6 Least significant bits of ADRESL
							; are read as '0'
							;AN0 is analog input, rest
							; of portA is digital
	bsf		STATUS,RP0		;Bank 1 select
	movwf	ADCON1
	bcf		STATUS,RP0		;Bank 0 select
	movlw	B'01000000'		;A/D conversion clock setup
							; TAD=8
							;Channel 0 selection RA0/AN0
	movwf	ADCON0
	bsf		ADCON0,0		;turn ON A/D converter module
;End Analog Setup

;Skip the following section, due to changeup on how the dispaly will scroll
	goto	skipStatic

skipStatic
;Clear out screen bytes
	clrf	RowDatHA
	clrf	RowDatHB
	clrf	RowDatHC
	clrf	RowDatHD
	clrf	RowDatHE
	clrf	RowDatHF
	clrf	RowDatHG
	clrf	RowDatHH

;	movlw	0xFF
;	movwf	RowDatMA
;	movwf	RowDatMB
;	movwf	RowDatMC
;	movwf	RowDatMD
;	movwf	RowDatME
;	movwf	RowDatMF
;	movwf	RowDatMG
;	movwf	RowDatMH
	
	clrf	RowDatMA
	clrf	RowDatMB
	clrf	RowDatMC
	clrf	RowDatMD
	clrf	RowDatME
	clrf	RowDatMF
	clrf	RowDatMG
	clrf	RowDatMH

	clrf	RowDatLA
	clrf	RowDatLB
	clrf	RowDatLC
	clrf	RowDatLD
	clrf	RowDatLE
	clrf	RowDatLF
	clrf	RowDatLG
	clrf	RowDatLH

	clrf	RowDatLLA
	clrf	RowDatLLB
	clrf	RowDatLLC
	clrf	RowDatLLD
	clrf	RowDatLLE
	clrf	RowDatLLF
	clrf	RowDatLLG
	clrf	RowDatLLH

	clrf	RowDatBufA
	clrf	RowDatBufB
	clrf	RowDatBufC
	clrf	RowDatBufD
	clrf	RowDatBufE
	clrf	RowDatBufF
	clrf	RowDatBufG
	clrf	RowDatBufH

;Load top row of display into RowDatLL. . .H
	movf	RowDatLLA,w		
	movwf	RowDatLL

	movf	RowDatLA,w
	movwf	RowDatL

	movf	RowDatMA,w
	movwf	RowDatM

	movf	RowDatHA,w
	movwf	RowDatH

	movlw	B'00000010'
	movwf	DDRAMPos		;Place start position at second
							; row of display, due to first row
							; being loaded and serviced already

	clrf	Timer			;Clear timer for alternating messages

	bsf		INTCON,PEIE		;Enable Peripheral Interrupts
	bsf		INTCON,GIE		;Global Interrupt Enable
;End Setup

;****************************************
;	Main Program
;		Performs all math operations general operations
;		This will be constantly interrupted
;		by TMR2
;****************************************
Main
;Set timers to cycle through the scrolling letters
;	movlw	0x80
;	movwf	RowDatBufA
;	movwf	RowDatBufB
;	movwf	RowDatBufC
;	movwf	RowDatBufD
;	movwf	RowDatBufE
;	movwf	RowDatBufF
;	movwf	RowDatBufG
;	movwf	RowDatBufH	

;Load letter into buffer
	movlw	letO		;O
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf	

	movlw	letM		;M
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letA		;A
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letH		;H
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letA		;A
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	letM		;M
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letI		;I
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letN		;N
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letI		;I
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	letM		;M
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letA		;A
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letK		;K
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letE		;E
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letR		;R
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	letF		;F
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letA		;A
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letI		;I
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letR		;R
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	letE		;E
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	num2		;2
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	letO		;0
	movwf	LtrOfst
	call	LdLtrBuf
	call	CycBuf

	movlw	num1		;1
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	num4		;4
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

	movlw	symSpace	;Space
	movwf	LtrOfst
	call	LdNmbrBuf
	call	CycBuf

;Create animation here.

	goto	Main

;****************************************
;
;General purpose Subroutines
;
;****************************************

;****************************************
;Cycle through buffer according to width assigned
;	uses built in timer to cycle through the entire 
;	buffer width utilized
; Variables used:
;	LtrPnt		will need to be loaded with buffers width
;****************************************
CycBuf
;Load analog value into timer for Matrix Scrolling Speed
	bsf		ADCON0,2		;convert analog to digital 
							; ON
Ac	btfsc	ADCON0,2		;wait for conversion to complete
	goto	Ac

;Need to have only 5 bits of resolution
	movf	ADRESH,w		;move upper 8 bits to WREG
	movwf	MatrixSpeed
	rrf		MatrixSpeed		;Move upper 5 sig. bits to
	rrf		MatrixSpeed		; lower 5
	rrf		MatrixSpeed
	movf	MatrixSpeed,w	;Place back into WREG
	andlw	B'00011111'		;Mask upper 3
	btfsc	STATUS,Z	
	goto	Max
	goto	Countdown

Max
	movlw	B'00000001'

Countdown
	movwf	MatrixSpeed
	movwf	Delay2
	call	Delay2Sec
	movf	MatrixSpeed,w
	movwf	Delay2
	call	Delay2Sec
	call	ShftLeft		;Shift 1 column from buffer into display
	decfsz	LtrPnt
	goto	CycBuf
	return

;****************************************
;Load letter or numbers called into buffer
;	This will only load the letters organized
;	 in 0x300 area and will not load in 0x400 area
;
;	Call LdLtrBuf to load letters into buffer
;	Call LdNmbrBuf to load numbers or symbols into buffer
;
; Variables used:
;	LtrOfst		Load with offset to point
;				 to correct letter in table
;	LtrPnt		will be loaded with width of letter
;
;	
;****************************************
LdLtrBuf
	movlw	HIGH Ltrs
	movwf	HiPnt
	
	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	LtrPnt
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufA
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufB
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufC
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufD
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufE
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufF
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufG
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	Ltrs
	movwf	RowDatBufH
	incf	LtrOfst	
	return

LdNmbrBuf
	movlw	HIGH NumSym
	movwf	HiPnt
	
	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	LtrPnt
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufA
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufB
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufC
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufD
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufE
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufF
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufG
	incf	LtrOfst	

	movf	HiPnt,w
	movwf	PCLATH
	movf	LtrOfst,w
	call	NumSym
	movwf	RowDatBufH
	incf	LtrOfst	
	return
;****************************************

;****************************************
;Shift Screen left pulling data from RowDatBuf
;****************************************
ShftLeft	
	addlw	0x00			;Clear Carry
	rlf		RowDatBufA
	rlf		RowDatLLA
	rlf		RowDatLA
	rlf		RowDatMA
	rlf		RowDatHA
	
	addlw	0x00			;Clear Carry
	rlf		RowDatBufB
	rlf		RowDatLLB
	rlf		RowDatLB
	rlf		RowDatMB
	rlf		RowDatHB

	addlw	0x00			;Clear Carry
	rlf		RowDatBufC
	rlf		RowDatLLC
	rlf		RowDatLC
	rlf		RowDatMC
	rlf		RowDatHC

	addlw	0x00			;Clear Carry
	rlf		RowDatBufD
	rlf		RowDatLLD
	rlf		RowDatLD
	rlf		RowDatMD
	rlf		RowDatHD

	addlw	0x00			;Clear Carry
	rlf		RowDatBufE
	rlf		RowDatLLE
	rlf		RowDatLE
	rlf		RowDatME
	rlf		RowDatHE

	addlw	0x00			;Clear Carry
	rlf		RowDatBufF
	rlf		RowDatLLF
	rlf		RowDatLF
	rlf		RowDatMF
	rlf		RowDatHF

	addlw	0x00			;Clear Carry
	rlf		RowDatBufG
	rlf		RowDatLLG
	rlf		RowDatLG
	rlf		RowDatMG
	rlf		RowDatHG

	addlw	0x00			;Clear Carry
	rlf		RowDatBufH
	rlf		RowDatLLH
	rlf		RowDatLH
	rlf		RowDatMH
	rlf		RowDatHH
	return
;****************************************

;*********************************
;	Delay2Sec subroutine is used
;		for general purpose
;		stalling
;	Load Delay2 with a value
;	 to change speed of display
;*********************************
Delay2Sec
	movwf	Delay2
Delay2SecA	
	movf	Delay2,w
	call	Delay20ms
	decfsz	Delay2
	goto	Delay2SecA
	return

;*********************************
;	Delay20ms subroutine 
;*********************************
Delay20ms
	movlw	.26				;Set outer loop to 12
	movwf	Outer
D1
	clrf	Inner			;Clear inner loop
D2
	decfsz	Inner		
	goto	D2
	decfsz	Outer
	goto	D1
	return


;****************************************
;	Subroutine
;		The interrupt timer runs evry 9.6 microS
;****************************************
IntService
	MOVWF	WTemp			;Copy W to TEMP register
	SWAPF	STATUS,W		;Swap status to be saved into W
	CLRF	STATUS			;bank 0, regardless of current bank, Clears IRP,RP1,RP0
	MOVWF	StatTemp		;Save status to bank zero STATUS_TEMP register
	MOVF	PCLATH, W		;Only required if using pages 1, 2 and/or 3
	MOVWF	PCLTemp			;Save PCLATH into W
	CLRF	PCLATH			;Page zero, regardless of current page
	BCF		STATUS, RP1		;
	BCF		STATUS, RP0		;Bank 0 Select

Timer2Chk
	btfss	PIR1,1			;Check Timer2 Flag
	goto	IntExit			; goto end or subroutine

	btfss	Mat_Info,0		;Check if data or clock needs to cycle
	goto	CycleData

;****************************************
;	The following section is for
;		cycling the clocks.  There
;		are three seperate clocks that 
;		are driven here:
;
;		Column Clock (Col_Clock):
;			_-_-_-_-_-_-_-_____
;			(clocks 8 pulses to select row)
;
;		Row Clock (Row_Clock)
;			_-_-_-_-_-_-..._-_-______
;			(clocks 32 pulses for row data on first display)
;
;		Row2 Clock (Row2_Clock)
;			_-_-_-_-_-_-..._-_-______
;			(clocks 32 pulses for row data on second display)
		

CycleClock
	btfss	Mat_Info,1		;Check if Columns or Rows need to cycle
	goto	CycleRow

CycleColumn
	decfsz	Col_Cnt
	goto	ColClkHigh
	movlw	B'00001000'		;Reset Column Counter
	movwf	Col_Cnt
	bcf		Mat_Info,1		;Rows now needs to be serviced
	addlw	0x00			;Clear Carry
	rrf		Col_Dat			;Shift Col_Dat for next column
	btfsc	STATUS,C		;Check for carry
	goto	Col_Dat_Reset
	goto	ColClkHigh

Col_Dat_Reset
	bsf		Col_Dat,7		;Reset cycle	

ColClkHigh
	bcf		PORTC,Col_Clock
	bcf		Mat_Info,0		;Data needs to be serviced next
	goto	Timer2Reset

CycleRow
	decfsz	Row_Cnt			;Row count has reached zero
	goto	RowClkHigh

;could modify following code to reload the serviced row pulling from 
; a fully mapped screen.  This would allow for a game to be created.
;Address the whole screen by bytes.
; will need to follow a matrix shift to point to different rows.
	
;Following code is used to increment to next row for display 1

;Check which row we are in A...H
;	Then load visible row with the correct display row
;	Use DDRAMPos to find correct row
	btfsc	DDRAMPos,0		;Row A is current row
	goto	ServA

	btfsc	DDRAMPos,1		;Row A is current row
	goto	ServB

	btfsc	DDRAMPos,2		;Row A is current row
	goto	ServC

	btfsc	DDRAMPos,3		;Row A is current row
	goto	ServD

	btfsc	DDRAMPos,4		;Row A is current row
	goto	ServE

	btfsc	DDRAMPos,5		;Row A is current row
	goto	ServF

	btfsc	DDRAMPos,6		;Row A is current row
	goto	ServG

	btfsc	DDRAMPos,7		;Row A is current row
	goto	ServH

ServA
	movf	RowDatLLA,w		
	movwf	RowDatLL
	movf	RowDatLA,w
	movwf	RowDatL
	movf	RowDatMA,w
	movwf	RowDatM
	movf	RowDatHA,w
	movwf	RowDatH
	movlw	B'00000010'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServB
	movf	RowDatLLB,w		
	movwf	RowDatLL
	movf	RowDatLB,w
	movwf	RowDatL
	movf	RowDatMB,w
	movwf	RowDatM
	movf	RowDatHB,w
	movwf	RowDatH
	movlw	B'00000100'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServC
	movf	RowDatLLC,w		
	movwf	RowDatLL
	movf	RowDatLC,w
	movwf	RowDatL
	movf	RowDatMC,w
	movwf	RowDatM
	movf	RowDatHC,w
	movwf	RowDatH
	movlw	B'00001000'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServD
	movf	RowDatLLD,w		
	movwf	RowDatLL
	movf	RowDatLD,w
	movwf	RowDatL
	movf	RowDatMD,w
	movwf	RowDatM
	movf	RowDatHD,w
	movwf	RowDatH
	movlw	B'00010000'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServE
	movf	RowDatLLE,w		
	movwf	RowDatLL
	movf	RowDatLE,w
	movwf	RowDatL
	movf	RowDatME,w
	movwf	RowDatM
	movf	RowDatHE,w
	movwf	RowDatH
	movlw	B'00100000'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServF
	movf	RowDatLLF,w		
	movwf	RowDatLL
	movf	RowDatLF,w
	movwf	RowDatL
	movf	RowDatMF,w
	movwf	RowDatM
	movf	RowDatHF,w
	movwf	RowDatH
	movlw	B'01000000'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServG
	movf	RowDatLLG,w		
	movwf	RowDatLL
	movf	RowDatLG,w
	movwf	RowDatL
	movf	RowDatMG,w
	movwf	RowDatM
	movf	RowDatHG,w
	movwf	RowDatH
	movlw	B'10000000'
	movwf	DDRAMPos		;Select next row to be serviced
	goto	RowsServiced

ServH
	movf	RowDatLLH,w		
	movwf	RowDatLL
	movf	RowDatLH,w
	movwf	RowDatL
	movf	RowDatMH,w
	movwf	RowDatM
	movf	RowDatHH,w
	movwf	RowDatH
	movlw	B'00000001'
	movwf	DDRAMPos		;Select first row to be serviced

RowsServiced
	bsf		Mat_Info,1		;Columns now needs to be serviced

	bcf		Mat_Info,0		;cycle data

;Place timer here to shift data

	movlw	B'00100001'		;Reset Row Counter to 32
	movwf	Row_Cnt
	goto	Timer2Reset

MidDisp
	movlw	B'00100000'		;Reset Row Counter to 32
	movwf	Row_Cnt
	goto	Timer2Reset

RowClkHigh
	bcf		PORTC,Row_Clock
	bcf		Mat_Info,0		;Data needs to be serviced next
	goto	Timer2Reset

CycleData
	btfss	Mat_Info,1		;Check if Rows or Columns data is output
	goto	CycRowDat

CycColDat
	bsf		PORTC,Row_Clock
	bsf		PORTC,Col_Clock
	movf	Col_Dat,w
	addlw	0x00			;Clear Carry bit
	rrf		Col_Dat
	movf	Col_Dat,w
	btfsc	STATUS,C		;Check for carry
	goto	Col_Reset
	bcf		PORTC,Data_Line
	bsf		Mat_Info,0		;Clock needs to be serviced next
	goto	Timer2Reset

Col_Reset
	bsf		Col_Dat,7		;Reset cycle
	bsf		PORTC,Data_Line
	bsf		Mat_Info,0		;Clock needs to be serviced next	
	goto	Timer2Reset	

CycRowDat
	bsf		PORTC,Row_Clock
	bsf		PORTC,Col_Clock
	addlw	0x00			;Clear Carry bit
	rrf		RowDatH			;setup to output next bit
	rrf		RowDatM
	rrf		RowDatL
	rrf		RowDatLL
	btfsc	STATUS,C		;Check for carry
	goto	Row_Reset
	bcf		PORTC,Data_Line
	bsf		Mat_Info,0		;Clock needs to be serviced next
	goto	Timer2Reset

Row_Reset
	bsf		RowDatH,7		;Not sure why this is set when the next row should be reset anyways
	bsf		PORTC,Data_Line
	bsf		Mat_Info,0		;Clock needs to be serviced next	
	goto	Timer2Reset	

Timer2Reset
	bcf		PIR1,1			;Reset Timer2 Flag

IntExit
	bcf		STATUS,RP0		;Bank 0 Select
	MOVF	PCLTemp, W		;Restore PCLATH
	MOVWF	PCLATH			;Move W into PCLATH
	SWAPF	StatTemp,W		;Swap STATUS_TEMP register into W
							;(sets bank to original state)
	MOVWF	STATUS			;Move W into STATUS register
	SWAPF	WTemp,F			;Swap W_TEMP
	SWAPF	WTemp,W			;Swap W_TEMP into W	
	retfie
;****************************************


;****************************************
;Subroutines
;	Ltrs retains letters
;	NumSym retains numbers and symbols
;****************************************
org	0x300

;Letter "D"
Ltrs
	addwf PCL,F ;add offset to pc to
	retlw 0x05				;This will be used to show how wide
							; the letter is. A 0
	retlw B'10010000'		;A	is bottom
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11110000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H is top

	retlw 0x05				;This will be used to show how wide
							; the letter is. B 9
	retlw B'11100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11100000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. C 18
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10000000'		;C
	retlw B'10000000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. D 27
	retlw B'11100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'10010000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. E 36
	retlw B'11110000'		;A
	retlw B'10000000'		;B
	retlw B'10000000'		;C
	retlw B'11000000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10000000'		;G
	retlw B'11110000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. F 45
	retlw B'10000000'		;A
	retlw B'10000000'		;B
	retlw B'10000000'		;C
	retlw B'11000000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10000000'		;G
	retlw B'11110000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. G 54
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'10110000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. H 63
	retlw B'10010000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11110000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'10010000'		;H

	retlw 0x04				;This will be used to show how wide
							; the letter is. I 72
	retlw B'11100000'		;A
	retlw B'01000000'		;B
	retlw B'01000000'		;C
	retlw B'01000000'		;D
	retlw B'01000000'		;E
	retlw B'01000000'		;F
	retlw B'01000000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. J 81
	retlw B'01000000'		;A
	retlw B'10100000'		;B
	retlw B'00100000'		;C
	retlw B'00100000'		;D
	retlw B'00100000'		;E
	retlw B'00100000'		;F
	retlw B'00100000'		;G
	retlw B'01110000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. K 90
	retlw B'10010000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11100000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'10010000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. L 99
	retlw B'11110000'		;A
	retlw B'10000000'		;B
	retlw B'10000000'		;C
	retlw B'10000000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10000000'		;G
	retlw B'10000000'		;H

	retlw 0x06				;This will be used to show how wide
							; the letter is. M 108
	retlw B'10001000'		;A
	retlw B'10001000'		;B
	retlw B'10001000'		;C
	retlw B'10001000'		;D
	retlw B'10001000'		;E
	retlw B'10101000'		;F
	retlw B'11011000'		;G
	retlw B'10001000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. N 117
	retlw B'10010000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'10110000'		;D
	retlw B'10110000'		;E
	retlw B'10110000'		;F
	retlw B'11010000'		;G
	retlw B'11010000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. O 126
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'10010000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. P 135
	retlw B'10000000'		;A
	retlw B'10000000'		;B
	retlw B'10000000'		;C
	retlw B'11100000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. Q 144
	retlw B'01010000'		;A
	retlw B'10100000'		;B
	retlw B'10010000'		;C
	retlw B'10010000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. R 153
	retlw B'10010000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11100000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. S 162
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'00010000'		;C
	retlw B'01100000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x04				;This will be used to show how wide
							; the letter is. T 171
	retlw B'01000000'		;A
	retlw B'01000000'		;B
	retlw B'01000000'		;C
	retlw B'01000000'		;D
	retlw B'01000000'		;E
	retlw B'01000000'		;F
	retlw B'01000000'		;G
	retlw B'11100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. U 180
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'10010000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'10010000'		;H

	retlw 0x04				;This will be used to show how wide
							; the letter is. V 189
	retlw B'01000000'		;A
	retlw B'10100000'		;B
	retlw B'10100000'		;C
	retlw B'10100000'		;D
	retlw B'10100000'		;E
	retlw B'10100000'		;F
	retlw B'10100000'		;G
	retlw B'10100000'		;H

	retlw 0x06				;This will be used to show how wide
							; the letter is. W 198
	retlw B'01010000'		;A
	retlw B'10101000'		;B
	retlw B'10101000'		;C
	retlw B'10101000'		;D
	retlw B'10101000'		;E
	retlw B'10101000'		;F
	retlw B'10101000'		;G
	retlw B'10101000'		;H

	retlw 0x04				;This will be used to show how wide
							; the letter is. X 207
	retlw B'10100000'		;A
	retlw B'10100000'		;B
	retlw B'10100000'		;C
	retlw B'01000000'		;D
	retlw B'01000000'		;E
	retlw B'10100000'		;F
	retlw B'10100000'		;G
	retlw B'10100000'		;H

	retlw 0x04				;This will be used to show how wide
							; the letter is. Y 216
	retlw B'01000000'		;A
	retlw B'01000000'		;B
	retlw B'01000000'		;C
	retlw B'01000000'		;D
	retlw B'10100000'		;E
	retlw B'10100000'		;F
	retlw B'10100000'		;G
	retlw B'10100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. Z 225
	retlw B'11110000'		;A
	retlw B'10000000'		;B
	retlw B'01000000'		;C
	retlw B'01000000'		;D
	retlw B'00100000'		;E
	retlw B'00100000'		;F
	retlw B'00010000'		;G
	retlw B'11110000'		;H

org	0x400
NumSym
	addwf PCL,F ;add offset to pc to
	retlw 0x04				;This will be used to show how wide
							; the letter is. 1 0
	retlw B'11100000'		;A
	retlw B'01000000'		;B
	retlw B'01000000'		;C
	retlw B'01000000'		;D
	retlw B'01000000'		;E
	retlw B'01000000'		;F
	retlw B'11000000'		;G
	retlw B'01000000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 2 9
	retlw B'11110000'		;A
	retlw B'10000000'		;B
	retlw B'01000000'		;C
	retlw B'00100000'		;D
	retlw B'00010000'		;E
	retlw B'00010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 3 18
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'00010000'		;C
	retlw B'00010000'		;D
	retlw B'00100000'		;E
	retlw B'00010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 4 27
	retlw B'00010000'		;A
	retlw B'00010000'		;B
	retlw B'00010000'		;C
	retlw B'11110000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'10010000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 5 36
	retlw B'11100000'		;A
	retlw B'00010000'		;B
	retlw B'00010000'		;C
	retlw B'11100000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10000000'		;G
	retlw B'11110000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 6 45
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'11100000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 7 54
	retlw B'01000000'		;A
	retlw B'01000000'		;B
	retlw B'01000000'		;C
	retlw B'00100000'		;D
	retlw B'00100000'		;E
	retlw B'00010000'		;F
	retlw B'10010000'		;G
	retlw B'11110000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 8 63
	retlw B'01100000'		;A
	retlw B'10010000'		;B
	retlw B'10010000'		;C
	retlw B'01100000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. 9 72
	retlw B'00010000'		;A
	retlw B'00010000'		;B
	retlw B'00010000'		;C
	retlw B'01110000'		;D
	retlw B'10010000'		;E
	retlw B'10010000'		;F
	retlw B'10010000'		;G
	retlw B'01100000'		;H

	retlw 0x05				;This will be used to show how wide
							; the letter is. Long Space 81
	retlw B'00000000'		;A
	retlw B'00000000'		;B
	retlw B'00000000'		;C
	retlw B'00000000'		;D
	retlw B'00000000'		;E
	retlw B'00000000'		;F
	retlw B'00000000'		;G
	retlw B'00000000'		;H

	retlw 0x06				;This will be used to show how wide
							; the letter is. Wide Exclamation Point 90
	retlw B'01000000'		;A
	retlw B'00000000'		;B
	retlw B'00000000'		;C
	retlw B'01000000'		;D
	retlw B'01000000'		;E
	retlw B'10100000'		;F
	retlw B'10100000'		;G
	retlw B'01000000'		;H

	retlw 0x02				;This will be used to show how wide
							; the letter is. Thin Exclamation Point 99
	retlw B'10000000'		;A
	retlw B'00000000'		;B
	retlw B'00000000'		;C
	retlw B'10000000'		;D
	retlw B'10000000'		;E
	retlw B'10000000'		;F
	retlw B'10000000'		;G
	retlw B'10000000'		;H

	retlw 0x09				;This will be used to show how wide
							; the letter is. Equal sign 108
	retlw B'00000000'		;A
	retlw B'00000000'		;B
	retlw B'00000000'		;C
	retlw B'11111111'		;D
	retlw B'00000000'		;E
	retlw B'11111111'		;F
	retlw B'00000000'		;G
	retlw B'00000000'		;H

;****************************************

	end
