;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     config.asm                                                 *
;*   Description:                                                             *
;*   Last mod:     11 august 2012                                             *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************
include <p18f2520.inc>


#define ADDR_CFG_PRESENT			0x00
#define	ADDR_LCD_CONTRAST			0x01
#define ADDR_LCD_BACKLIGHT			0x02
#define ADDR_LCD_MODE				0x03
#define ADDR_LCD_BOOTOPT			0x04
#define ADDR_LCD_BACKLIGHT_DIM		0x05
#define ADDR_LCD_BACKLIGHT_OPT		0x06
#define ADDR_LCD_BOOTDATA			0x10
#define ADDR_LCD_CUSTOM_CHARS		0x40



;==============================================================================
;==============================================================================
;
;                                     Data   
;------------------------------------------------------------------------------
; Access bank
.a_config		UDATA_ACS
cfg_lcd_contr	RES		0x01				; LCD contrast				
cfg_lcd_bl		RES		0x01				; LCD backlight level (normal)
cfg_lcd_bldim	RES		0x01				; LCD backlight level (dim)
cfg_lcd_dimdl	RES		0x01				; LCD backlight auto-dim delay
cfg_lcd_brate	RES		0x01				; LCD backlight blink rate
cfg_lcd_mode	RES		0x01				; LCD display mode
cfg_lcd_bsopt	RES		0x01				; Bootscreen options
cfg_lcd_bdata	RES		0x20				; Bootscreen data
i				RES		0x01				; Iteration counter



;==============================================================================
;==============================================================================
;
;                                   Symbols 
;------------------------------------------------------------------------------
; *** Subroutines ***
GLOBAL		load_config						; Load configuration from EEPROM
GLOBAL		load_attrib_config				; Load attributes from EEPROM
GLOBAL		save_config						; Save configuration to EEPROM
GLOBAL		write_eeprom					; Write byte to EEPROM
GLOBAL		read_eeprom						; Read byte from EEPROM
; *** Variables ***		
GLOBAL		cfg_lcd_contr					; LCD contrast
GLOBAL		cfg_lcd_bl						; LCD backlight
GLOBAL		cfg_lcd_bldim					; LCD backlight (dim)
GLOBAL		cfg_lcd_dimdl					; LCD backlight options
GLOBAL		cfg_lcd_mode					; LCD display mode
GLOBAL		cfg_lcd_bsopt					; LCD boot screen options
GLOBAL		cfg_lcd_bdata					; LCD boot screen data
GLOBAL		cfg_lcd_brate			

; *** External symbols ***
EXTERN		lcd_save_cgram_table
EXTERN		lcd_load_cgram_table
EXTERN		lcd_read_eeprom
EXTERN		lcd_write_eeprom



;==============================================================================
;==============================================================================
;
;                                Subroutines 
;------------------------------------------------------------------------------
.c_config		CODE


;******************************************************************************
; load_attrib_config : Load attributes configuration from EEPROM
;
; Arguments : None
; Return	: None
;******************************************************************************
load_attrib_config:
		movlw	ADDR_CFG_PRESENT
		rcall	read_eeprom
		
		xorlw	0xFF
		btfsc	STATUS, Z
		bra		default_attrib_config	
		
		movlw	ADDR_LCD_CONTRAST
		rcall	read_eeprom
		movwf	cfg_lcd_contr
		
		movlw	ADDR_LCD_BACKLIGHT
		rcall	read_eeprom
		movwf	cfg_lcd_bl
		
		movlw	ADDR_LCD_BACKLIGHT_DIM
		rcall	read_eeprom
		movwf	cfg_lcd_bldim
		
		movlw	ADDR_LCD_BACKLIGHT_OPT
		rcall	read_eeprom
		movwf	cfg_lcd_dimdl
		
		clrf	cfg_lcd_brate
		
		return

;------------------------------------------------------------------------------
; Default attributes 
;------------------------------------------------------------------------------
default_attrib_config:
		movlw	D'180'
		movwf	cfg_lcd_bl
		
		movlw	D'25'
		movwf	cfg_lcd_bldim
		
		movlw	D'190'
		movwf	cfg_lcd_contr
		
		clrf	cfg_lcd_dimdl
		clrf	cfg_lcd_brate
		
		return 


;******************************************************************************
; load_attrib_config : Load general configuration from EEPROM
;
; Arguments : None
; Return	: None
;******************************************************************************
load_config:
		movlw	ADDR_CFG_PRESENT
		rcall	read_eeprom
		
		xorlw	0xFF
		btfsc	STATUS, Z
		bra		default_config	

		movlw	ADDR_LCD_MODE
		rcall	read_eeprom
		movwf	cfg_lcd_mode
		bsf		cfg_lcd_mode, 2				; Display on-off bit is always on
		
		movlw	ADDR_LCD_BOOTOPT
		rcall	read_eeprom
		movwf	cfg_lcd_bsopt

		lfsr	FSR0, cfg_lcd_bdata+0
		movlw	ADDR_LCD_BOOTDATA
		movwf	EEADR
		
		movlw	D'32'
		movwf	i
		
loop_read_char:
		movf	EEADR, W
		rcall	read_eeprom
		movwf	POSTINC0
		
		incf	EEADR
		
		decfsz	i
		bra		loop_read_char

		movlw	ADDR_LCD_CUSTOM_CHARS
		movwf	EEADR

		rcall	lcd_load_cgram_table
		
		call	load_attrib_config
		
		return		

;------------------------------------------------------------------------------
; Default config
;------------------------------------------------------------------------------
default_config:
		movlw	0x07
		movwf	cfg_lcd_mode
		
		movlw	0x00
		movwf	cfg_lcd_bsopt
		
		return


;******************************************************************************
; save_config : Save configuration to EEPROM
;
; Arguments : None
; Return	: None
;******************************************************************************		
save_config:
		movlw	ADDR_CFG_PRESENT
		movwf	EEADR
		clrf	EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_CONTRAST
		movwf	EEADR
		movff	cfg_lcd_contr, EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_BACKLIGHT
		movwf	EEADR
		movff	cfg_lcd_bl, EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_BACKLIGHT_DIM
		movwf	EEADR
		movff	cfg_lcd_bldim, EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_BACKLIGHT_OPT
		movwf	EEADR
		movff	cfg_lcd_dimdl, EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_MODE
		movwf	EEADR
		movff	cfg_lcd_mode, EEDATA
		rcall	write_eeprom
		
		movlw	ADDR_LCD_BOOTOPT
		movwf	EEADR
		movff	cfg_lcd_bsopt, EEDATA
		rcall	write_eeprom
		
		
		movlw	ADDR_LCD_BOOTDATA
		movwf	EEADR
		
		lfsr	FSR0, cfg_lcd_bdata+0
		
		movlw	D'32'
		movwf	i
			
loop_write_char:		
		
		movff	POSTINC0, EEDATA
		rcall	write_eeprom

		incf	EEADR
		
		decfsz	i
		bra		loop_write_char

		movlw	ADDR_LCD_CUSTOM_CHARS
		movwf	EEADR

		rcall	lcd_save_cgram_table

		return


;******************************************************************************
; read_eeprom : Read byte from EEPROM
;
; Arguments : W= Address
; Return	: None
;******************************************************************************
read_eeprom:
		clrf	EECON1
		
		movwf	EEADR
		
		bsf		EECON1, RD
		movf	EEDATA, W

		return


;******************************************************************************
; write_eeprom : Write byte to eeprom
;
; Arguments : EEDATA= byte to write, EEADR= address
; Return	: None
;******************************************************************************
write_eeprom:
		bcf		INTCON, GIE
		
		clrf	EECON1
		bsf		EECON1, WREN
		
		movlw	0x55
		movwf	EECON2
		movlw	0xAA
		movwf	EECON2
		
		bsf		EECON1, WR
		bsf		INTCON, GIE

loop_wait_wr:
		btfss	PIR2, EEIF
		bra		loop_wait_wr
		
		bcf		PIR2, EEIF
		bcf		EECON1, WREN

		return
		
		
;==============================================================================
;==============================================================================
		END		
