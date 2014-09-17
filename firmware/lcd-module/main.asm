;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     main.asm                                                   *
;*   Description:                                                             *
;*   Last mod:     15 july 2013                                               *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************
include <p18f2520.inc>
include "macro.inc"

;==============================================================================
;==============================================================================
;
;                                   Symbols 
;------------------------------------------------------------------------------
; *** External symbols ***
EXTERN      lcd_clear
EXTERN      lcd_clear_to
EXTERN      lcd_clear_pages
EXTERN      lcd_goto
EXTERN      lcd_init
EXTERN      lcd_write
EXTERN      lcd_set_page
EXTERN      lcd_show_page
EXTERN      lcd_show_nextpage
EXTERN      lcd_show_prevpage
EXTERN      lcd_offset_pos
EXTERN      lcd_set_display
EXTERN      lcd_save_pos
EXTERN      lcd_restore_pos
EXTERN      lcd_trans_type
EXTERN      lcd_trans_speed
EXTERN      lcd_read_page
EXTERN      lcd_write_page
EXTERN      lcd_write_cgram
EXTERN      lcd_bptr

EXTERN      delay1ktcy
EXTERN      spi_init
EXTERN      mcp410xx_write
EXTERN      usart_init
EXTERN      usart_isr
EXTERN      usart_read_buffer
EXTERN      usart_write_byte
EXTERN      usart_buffer_len
EXTERN      load_config
EXTERN      load_attrib_config      
EXTERN      save_config

EXTERN      cfg_lcd_contr
EXTERN      cfg_lcd_bl
EXTERN      cfg_lcd_bldim
EXTERN      cfg_lcd_dimdl               
EXTERN      cfg_lcd_mode
EXTERN      cfg_lcd_bsopt
EXTERN      cfg_lcd_bdata
EXTERN      cfg_lcd_brate

EXTERN      charmap
EXTERN      charset
EXTERN      flookup

;==============================================================================
;==============================================================================
;
;                              Configuration bits
;------------------------------------------------------------------------------
CONFIG OSC=INTIO67
CONFIG PWRT=ON
CONFIG WDT=OFF
CONFIG PBADEN=OFF
CONFIG LVP=ON
CONFIG MCLRE=ON
CONFIG DEBUG=OFF



;==============================================================================
;==============================================================================
;
;                                    Data
;------------------------------------------------------------------------------
; Access bank
.a_main         UDATA_ACS
char            RES     0x01                ; RX character buffer
params          RES     0x03                ; Escape sequence parameters
buffer          RES     0x08                ; 8 char. buffer                
p_count         RES     0x01                ; Escape seq parameter count
t_seconds       RES     0x01                ; Second timer              
t_fsec          RES     0x01                ; 1/10sec timer
bl_state        RES     0x01                ; Backlight state
bl_value        RES     0x01                ; Backlight level
bigfont         RES     0x01                ; Big font mode
i               RES     0x01                ; Iteration counter
i2              RES     0x01                ; Iteration counter 2

p_tblptrl       RES     0x01
p_tblptrh       RES     0x01
p_tblptru       RES     0x01

;==============================================================================
;==============================================================================
;
;                                       IVT
;------------------------------------------------------------------------------
.i_reset        CODE    0x0400
        goto    main

.i_hi_int       CODE    0x0408
        goto    interrupts



;==============================================================================
;==============================================================================
;
;                                      Main  
;------------------------------------------------------------------------------
.c_main         CODE

main:
        
        ;--------------------------------
        ; Configure oscillator
        ;--------------------------------       
        movlw   0x72                        ; Int. osc @ 8Mhz
        movwf   OSCCON
        clrf    OSCTUNE                     
     
        ;--------------------------------
        ; Configure ports
        ;--------------------------------       
        clrf    TRISA
        movlw   0xF7
        movwf   TRISB
        movlw   0x80
        movwf   TRISC

        bcf     ADCON0, ADON                ; Disable A/D
        movlw   0x0F
        movwf   ADCON1

        clrf    LATA
        clrf    LATB
        clrf    LATC        
        bsf     LATC, LATC2

        ;--------------------------------
        ; initialize LCD
        ;--------------------------------       
        call    lcd_init                    ; Initialize LCD

        ;--------------------------------
        ; Load EEPROM configuration
        ;--------------------------------       
        call    load_config

        ;--------------------------------
        ; Configure PWM for backlight
        ;--------------------------------       
        movff   cfg_lcd_bl, CCPR1L          ; Set backlight PWM duty
        movlw   B'00000110'
        movwf   T2CON
        movlw   D'255'
        movwf   PR2
        movlw   0xC
        movwf   CCP1CON        

        ;--------------------------------
        ; Initialize peripherals
        ;--------------------------------       
        call    spi_init                    ; Init SPI bus
        
        movf    cfg_lcd_contr, W            
        call    mcp410xx_write              ; Init MCP410 for lcd contrast
        
        call   usart_init                   ; Init Usart

        ;--------------------------------
        ; Configure Timer1 module
        ;--------------------------------       
        movlw   B'10010000'                 ; Timer 1
        movwf   T1CON                       ; Prescaler 1:2, int clock
        movlw   D'60'                       ; 20 hz, 15536 period
        movwf   TMR1H
        movlw   D'176'
        movwf   TMR1L

        ;--------------------------------
        ; Configure interrupts
        ;--------------------------------       
        bcf     RCON, IPEN

        clrf    INTCON
        bsf     INTCON, INT0IE              ; Enable INT0 interrupt
        bsf     INTCON2, INTEDG0            ; Interrupt on low-to-high
        
        bsf     INTCON3, INT1IE             ; Enable INT1 interrupt
        bsf     INTCON2, INTEDG1            ; Interrupt on low-to-high

        bsf     PIE1, TMR1IE                ; Enable timer1 interrupt
        bcf     PIR1, TMR1IF                ; Clear timer1 interrupt flag
        
        bsf     INTCON, PEIE                ; Enable peripheral interrupts
        bsf     INTCON, GIE                 ; Enable global interrupts


        clrf    bl_state
        bsf     T1CON, TMR1ON


        ;--------------------------------
        ; Display boot screen
        ;--------------------------------       
        btfss   cfg_lcd_bsopt, 7
        bra     no_bootscreen

        lfsr    FSR0, cfg_lcd_bdata+0
        call    lcd_write_page

        clrf    t_fsec
        clrf    t_seconds
        incf    t_seconds
        
loop_bootscreen_wait:
        
        movf    cfg_lcd_bsopt, W
        andlw   0x7F
        cpfsgt  t_seconds
        bra     loop_bootscreen_wait

        call    usart_buffer_len
        btfsc   STATUS, Z
        bra     loop_bootscreen_wait
        
        call    lcd_clear        
        clrf    t_fsec
        clrf    t_seconds
        
no_bootscreen:
        clrf    bigfont

        movf    cfg_lcd_mode, W
        call    lcd_set_display

        
;------------------------------------------------------------------------------
; Main loop
;------------------------------------------------------------------------------
loop_main:
        clrf    p_count                     ; Clear parameter count
        clrf    params+0                    ; Clear parameters
        clrf    params+1                    
        clrf    params+2
        
        
        call    usart_read_buffer           ; Read next character
        movwf   char
        
        xorlw   D'27'                       ; Check if escape character
        bz      escape_char

        movlw   0x00
        cpfseq  bigfont
        bra     process_bigfont

send_reg_char:
        movf    char, W                     ; Send character to lcd buffer
        call    lcd_write

        bra     loop_main                   ; Loop


;------------------------------------------------------------------------------
; Process escape sequence
;------------------------------------------------------------------------------
escape_char:
        
        call    usart_read_buffer           ; Read next character
        movwf   char
        
        jmpif   char, "[", escape_seq
        jmpif   char, "O", control
        bra     loop_main


escape_seq:     
        lfsr    FSR0,   params+0            ; move FSR1 to first parameter
    
loop_read_args:

        call    usart_read_buffer           ; Read next character
        movwf   char

        xorlw   ";"                
        bnz     chkif_number

        movlw   D'3'                        ; Maximum 3 parameters
        cpfslt  p_count
        bra     chkif_cmd

        incf    FSR0L, F                    ; Move FSR1 to next parameter
        incf    p_count
        
        bra     loop_read_args
        
chkif_number:       
        movlw   D'47'                       ; Check if the character is a
        cpfsgt  char                        ; number (ascii > 47 and < 58)
        bra     chkif_cmd
        
        movlw   D'58'                       
        cpfslt  char                        ; If not, jump to chkif_cmd, 
        bra     chkif_cmd                   ; otherwhise, process the number
                                            ; and store it in the current
                                            ; parameter pointed by FSR1
        
        movlw   D'10'                       ; Multiply the current parameter by
        mulwf   INDF0                       ; 10
        movff   PRODL, INDF0
        
        movlw   D'48'                       ; Convert number ascii to base 10
        subwf   char, W                     ; value and add it to the current 
        addwf   INDF0, F                    ; parameter

        movlw   D'0'                        ; Increment parameter counter if
        cpfsgt  p_count                     ; this is the first argument
        incf    p_count

        bra     loop_read_args
        
chkif_cmd:

        ;*** ECMA-48 sequences ***
        jmpif   char, "@", cmd_blank
        jmpif   char, "A", cmd_move_up
        jmpif   char, "B", cmd_move_down
        jmpif   char, "C", cmd_move_right
        jmpif   char, "D", cmd_move_left
        jmpif   char, "E", cmd_rtn_down
        jmpif   char, "F", cmd_rtn_up
        jmpif   char, "G", cmd_goto_col
        jmpif   char, "H", cmd_goto
        jmpif   char, "J", cmd_clr_screen
        jmpif   char, "K", cmd_erase_line
        ;              L : not implemented
        ;              M : not implemented
        ;              P : not implemented
        ;              X : not implemented
        jmpif   char, "a", cmd_move_right
        ;              c : not implemented
        jmpif   char, "d", cmd_goto_row
        jmpif   char, "e", cmd_move_down
        jmpif   char, "f", cmd_goto     
        ;              g : not implemented      
        jmpif   char, "h", cmd_set_mode
        jmpif   char, "l", cmd_reset_mode
        jmpif   char, "m", cmd_set_attrib
        ;              n : not implemented
        ;              p : not implemented
        ;              q : not implemented
        ;              r : not implemented
        jmpif   char, "s", cmd_save_pos
        jmpif   char, "u", cmd_restore_pos
        
        ;*** Extended sequences ***
        jmpif   char, "v", cmd_set_buffer_page
        jmpif   char, "t", cmd_goto_page
        jmpif   char, "o", cmd_save_bootscreen
        
        jmpif   char, "w", cmd_save_config

        jmpif   char, "U", cmd_show_icon
        jmpif   char, "V", cmd_load_charset
        jmpif   char, "T", cmd_ext_char_table
        jmpif   char, "Y", cmd_set_custom_char
        jmpif   char, "Z", cmd_special_char
        jmpif   char, "!", cmd_reset
        
        goto    loop_main       

control:
        call   usart_read_buffer           ; Read next character
        movwf   char
        
        jmpif   char, "H", control_home
        jmpif   char, "F", control_end
        goto    loop_main




;------------------------------------------------------------------------------
;
; Commands
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; ESC [ {num} @ : Insert the indicated # of blank characters
;------------------------------------------------------------------------------
cmd_blank:
        movf    params+0
        btfsc   STATUS, Z
        goto    loop_main
        
        movlw   0x20
        call    lcd_write

        decf    params+0
        bra     cmd_blank

;------------------------------------------------------------------------------
; ESC [ {num} A : Move cursor up
;------------------------------------------------------------------------------
cmd_move_up:
        movlw   D'16'
        incf    params+0
        mulwf   params+0
        movf    PRODL, W
        negf    WREG
        
        call    lcd_offset_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} B : Move cursor down
; ESC [ {num} e
;------------------------------------------------------------------------------
cmd_move_down:
        movlw   D'16'
        incf    params+0
        mulwf   params+0
        movf    PRODL, W
        
        call    lcd_offset_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} C : Move cursor right
; ESC [ {num} a
;------------------------------------------------------------------------------
cmd_move_right:
        movlw   D'1'
        tstfsz  params+0
        movf    params+0, W
        
        call    lcd_offset_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} D : Move cursor left
;------------------------------------------------------------------------------
cmd_move_left:
        movlw   D'1'
        tstfsz  params+0
        movf    params+0, W
        negf    WREG
        
        call    lcd_offset_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} E : Move cursor down x row to column 1
;------------------------------------------------------------------------------
cmd_rtn_down:
        movlw   D'16'
        mulwf   params+0
        
        movlw   0x10
        andwf   lcd_bptr, W
        addwf   PRODL, W
        
        call    lcd_goto

        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} F : Move cursor up x row to column 1
;------------------------------------------------------------------------------
cmd_rtn_up:
        movlw   D'16'
        mulwf   params+0
        
        movlw   0x10
        andwf   lcd_bptr, W
        negf    PRODL
        addwf   PRODL, W
        
        call    lcd_goto

        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {num} G : Goto column x
;------------------------------------------------------------------------------
cmd_goto_col:
        tstfsz  params+0
        decf    params+0

        movlw   0x0F
        andwf   params+0

        movlw   0x10
        andwf   lcd_bptr, W
        addwf   params+0, W
        
        call    lcd_goto

        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {row};{col} H : Set cursor position
; ESC [ {row};{col} f
;------------------------------------------------------------------------------
cmd_goto:
        tstfsz  params+0
        decf    params+0
        
        tstfsz  params+1
        decf    params+1
        
        movlw   D'16'
        mulwf   params+0
        movf    PRODL, W
        addwf   params+1, W
        
        call    lcd_goto

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ {mode} J : Clear screen
; - (default) From cursor to end of display
; - 1J = from cursor to begin of display
; - 2J = entire display
;------------------------------------------------------------------------------
cmd_clr_screen:
        movff   lcd_bptr, params+2

        jmpif   params+0, 0x04, clr_allpages
        jmpif   params+0, 0x02, clr_scr

        movlw   0x01
        cpfseq  params+0
        movlw   0x20
        decf    WREG

        call    lcd_clear_to
        
        movf    params+2, W
        call    lcd_goto
        
        goto    loop_main

;*** Clear entire screen ****
clr_scr:        
        call    lcd_clear
        goto    loop_main
        
;*** Clear all pages ****       
clr_allpages:
        call    lcd_clear_pages
        goto    loop_main       
        

;------------------------------------------------------------------------------
; ESC [ {mode} K : Clear line
; - (default) From cursor to end of line
; - 1J = from cursor to begin of line
; - 2J = entire line
;------------------------------------------------------------------------------
cmd_erase_line:
        movff   lcd_bptr, params+2

        jmpif   params+0, 0x02, clr_line
        
        movlw   0x10
        andwf   lcd_bptr, W
        movwf   params+1
        
        movlw   0x01
        cpfseq  params+0
        movlw   0x10
        decf    WREG
        
        addwf   params+1, W
        call    lcd_clear_to    
        
        movf    params+2, W
        call    lcd_goto
        
        goto    loop_main
        
;*** Clear the entire line ****     
clr_line:
        movf    lcd_bptr, W
        andlw   0x10
        call    lcd_goto                    ; Goto the begining of the current
                                            ; line

        movf    lcd_bptr, W
        addlw   0xF 
        call    lcd_clear_to

        movf    params+2, W
        andlw   0x10
        call    lcd_goto

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ {row} d : Move cursor to the indicated row, current column
;------------------------------------------------------------------------------
cmd_goto_row:
        movlw   D'16'
        mulwf   params+0
        
        movf    lcd_bptr, W
        andlw   0xF
        addwf   PRODL, W
        
        call    lcd_goto
        
        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ {mode} h : Set display mode
;------------------------------------------------------------------------------
cmd_set_mode:
        jmpif   params+0, D'25', mode_set_cursor
        jmpif   params+0, D'26', mode_set_block
        jmpif   params+0, D'50', mode_set_display
        goto    loop_main
        
mode_set_cursor:
        bsf     cfg_lcd_mode, 1
        bra     set_display_mode

mode_set_display:
        bsf     cfg_lcd_mode, 2
        bra     set_display_mode

mode_set_block:     
        bsf     cfg_lcd_mode, 0
        bra     set_display_mode
        
;------------------------------------------------------------------------------
; ESC [ {mode} l : Reset display mode
;------------------------------------------------------------------------------
cmd_reset_mode:
        jmpif   params+0, D'25', mode_reset_cursor
        jmpif   params+0, D'26', mode_reset_block
        jmpif   params+0, D'50', mode_reset_display
        goto    loop_main
        
mode_reset_cursor:
        bcf     cfg_lcd_mode, 1
        bra     set_display_mode

mode_reset_display:
        bcf     cfg_lcd_mode, 2
        bra     set_display_mode

mode_reset_block:       
        bcf     cfg_lcd_mode, 0
        bra     set_display_mode

set_display_mode:
        movf    cfg_lcd_mode, W
        call    lcd_set_display
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {attrib};{value} m : Reset display mode (display=1, block=0, cursor=0)
;------------------------------------------------------------------------------
cmd_set_attrib:

        jmpif   params+0, D'0', attrib_default  
        jmpif   params+0, D'60', attrib_backlight
        jmpif   params+0, D'61', attrib_backlight_dim
        jmpif   params+0, D'65', attrib_bl_delay
        jmpif   params+0, D'68', attrib_bl_blink
        jmpif   params+0, D'70', attrib_contrast
        jmpif   params+0, D'40', attrib_normal_font
        jmpif   params+0, D'41', attrib_bigfont_style1
        jmpif   params+0, D'42', attrib_bigfont_style2
        jmpif   params+0, D'43', attrib_bigfont_style3
        jmpif   params+0, D'44', attrib_bigfont_style4


        goto    loop_main

;*** Reset all attributes ***
attrib_default:
        clrf    bigfont                     
        clrf    bl_state                    ; Reset backlight state

        clrf    t_seconds                   ; Reset auto-dim timer
        clrf    t_fsec
        
        call    load_attrib_config
        
        movff   cfg_lcd_bl, CCPR1L
        movf    cfg_lcd_contr, W
        call    mcp410xx_write
        
        goto    loop_main

;*** Set backlight level (normal) ***       
attrib_backlight:
        movff   params+1, cfg_lcd_bl
        
        btfss   bl_state, 6
        movff   params+1, CCPR1L

        goto    loop_main

;*** Set backlight level (when dimmed) ***
attrib_backlight_dim:
        movff   params+1, cfg_lcd_bldim

        goto    loop_main       

;*** Reset contrast level ***
attrib_contrast:
        movff   params+1, cfg_lcd_contr
        movf    params+1, W
        call    mcp410xx_write      
        
        goto    loop_main

;*** Set backlight dimming delay ***        
attrib_bl_delay:
        movff   params+1, cfg_lcd_dimdl
        
        goto    loop_main   

;*** Set backlight blinking rate ***        
attrib_bl_blink:
        movlw   D'60'
        cpfslt  params+1
        movwf   params+1

        movff   params+1, cfg_lcd_brate
        
        movlw   0xC0                        ; Reset blink counter
        andwf   bl_state
        
        bcf     bl_state, 7

        goto    loop_main


;*** Set normal font ***
attrib_normal_font:
        clrf    bigfont
        goto    loop_main


;*** Set big font : style 1 ***     
attrib_bigfont_style1:
        movlw   0x01
        movwf   bigfont

        movlw   0x00
        call    read_ext_charset        

        goto    loop_main

attrib_bigfont_style2:
        movlw   0x01
        movwf   bigfont

        movlw   0x01
        call    read_ext_charset        

        goto    loop_main

attrib_bigfont_style3:
        movlw   0x02
        movwf   bigfont

        movlw   0x02
        call    read_ext_charset        

        goto    loop_main

attrib_bigfont_style4:
        movlw   0x03
        movwf   bigfont

        movlw   0x03
        call    read_ext_charset        

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ s : Save cursor location
;------------------------------------------------------------------------------
cmd_save_pos:
        call    lcd_save_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ u : Restore cursor location
;------------------------------------------------------------------------------
cmd_restore_pos:
        call    lcd_restore_pos
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {id} v : Set buffer page
;------------------------------------------------------------------------------
cmd_set_buffer_page:
        movf    params+0, W
        call    lcd_set_page
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {id};{transition};{speed} t : Goto page
;------------------------------------------------------------------------------
cmd_goto_page:
        movff   params+1, lcd_trans_type
        movff   params+2, lcd_trans_speed

        movf    params+0, W
        call    lcd_show_page
        
        movlw   "o"
        call    usart_write_byte
        
        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ k : Save configuration to EEPROM
;------------------------------------------------------------------------------
cmd_save_config:
        call    save_config
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {enabled};{delay} o : Save bootscreen settings
;------------------------------------------------------------------------------
cmd_save_bootscreen:
        movff   params+1, cfg_lcd_bsopt
        movlw   0x7F
        andwf   cfg_lcd_bsopt

        tstfsz  params+0
        bsf     cfg_lcd_bsopt, 7
        
        lfsr    FSR0, cfg_lcd_bdata+0
        call    lcd_read_page
        
        goto    loop_main       

;------------------------------------------------------------------------------
; ESC [ {char} Z : Send special character
;------------------------------------------------------------------------------
cmd_special_char:
        movf    params+0, W
        call    lcd_write
        
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {id} Y : Set custom character
;------------------------------------------------------------------------------
cmd_set_custom_char:
        
        lfsr    FSR0, buffer+0
        
        movlw   D'8'
        movwf   i
        
loop_rx:
        call    usart_read_buffer
        movwf   POSTINC0
        
        decfsz  i
        bra     loop_rx
        

        lfsr    FSR0, buffer+0
        
        movf    params+0, W
        call    lcd_write_cgram
        
        goto    loop_main

;------------------------------------------------------------------------------
; ESC [ {id};{charmap_id} T : Load custom characters from extended character map
;------------------------------------------------------------------------------
cmd_ext_char_table:
        
        movf    params+1, W
        call    read_ext_char
        
        movf    params+0, W
        call    lcd_write_cgram

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ {charset_id} V : Load character set from program memory
;------------------------------------------------------------------------------
cmd_load_charset:
        movf    params+0, W
        call    read_ext_charset

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ {icon_id} U : Display an icon (3x2)
;------------------------------------------------------------------------------
cmd_show_icon:
        movlw   0x04
        addwf   params+0, W
        call    read_ext_charset

        movf    lcd_bptr, W                 ; Place the cursor on the first 
        andlw   0xF                         ; Row
        call    lcd_goto
        
        movlw   D'6'
        movwf   i

loop_show_icon:

        movf    i, W
        sublw   D'6'
        call    lcd_write

        movlw   D'4'                        ; After the 3rd character, move
        cpfseq  i                           ; to the second line
        bra     skip_change_line2
        
        movlw   D'13'
        call    lcd_offset_pos

skip_change_line2:

        decfsz  i
        bra     loop_show_icon

        movf    lcd_bptr, W                 ; Move cursor back on the first row
        andlw   0xF
        call    lcd_goto

        goto    loop_main


;------------------------------------------------------------------------------
; ESC [ ! : Reset
;------------------------------------------------------------------------------
cmd_reset:
        movff   params+0,   0x00
        movff   params+1,   0x01
        movff   params+2,   0x02
        
        reset

;------------------------------------------------------------------------------
; ESC O H : 
;------------------------------------------------------------------------------
control_home:
        movlw   D'0'
        call    lcd_goto
        
        goto    loop_main
        
;------------------------------------------------------------------------------
; ESC O F : 
;------------------------------------------------------------------------------
control_end:
        movlw   D'31'
        call    lcd_goto
        
        goto    loop_main




;------------------------------------------------------------------------------
;
; Big font printing
;
;------------------------------------------------------------------------------
process_bigfont:
        ltblptr flookup
        
        movff   char, buffer+0

        movlw   0x2D
        subwf   buffer+0
        
        movlw   0x02
        cpfslt  buffer+0
        decf    buffer+0
        
        movlw   0x0D
        cpfslt  buffer+0
        goto    send_reg_char
        
        
        movf    lcd_bptr, W                 ; Place the cursor on the first 
        andlw   0xF                         ; Row
        call    lcd_goto


        decf    bigfont, W
        mullw   D'78'
        addff16 PRODL,PRODH,TBLPTRL,TBLPTRH
        
        movlw   D'6'
        mulwf   buffer+0
        addff16 PRODL,PRODH,TBLPTRL,TBLPTRH

        
        movlw   D'6'
        movwf   i

        clrf    EECON1
        bsf     EECON1, EEPGD
        
loop_read_lookup_table              
        
        tblrd*+
        
        movf    TABLAT, W
        call    lcd_write
        
        movlw   D'4'                        ; After the 3rd character, move
        cpfseq  i                           ; to the second line
        bra     skip_change_line
        
        movlw   D'13'
        call    lcd_offset_pos

skip_change_line:       
        
        decfsz  i
        bra     loop_read_lookup_table
        
        movf    lcd_bptr, W                 ; Move cursor back on the first row
        andlw   0xF
        call    lcd_goto
        
        goto loop_main
        
        
        

;==============================================================================
;==============================================================================
;
;                                 Sub routines
;------------------------------------------------------------------------------

;******************************************************************************
; read_ext_char: Read extended character stored in code memory (charmap.asm)
;
; Arguments : W= Character id
; Return    : Character data is stored in buffer+0
;******************************************************************************
read_ext_char:
        mullw   D'8'                        ; Multiply W by 8
        
        ltblptr charmap                     ; Set table ptr to start of charmap

        addff16 PRODL,PRODH,TBLPTRL,TBLPTRH ; Offset table ptr by the result
                                            ; of the multiplication

        movlw   0x08
        movwf   i
 
        lfsr    FSR0, buffer+0

        clrf    EECON1
        bsf     EECON1, EEPGD

loop_read_progmem:
        tblrd*+
        movff   TABLAT, POSTINC0
        
        decfsz  i
        bra     loop_read_progmem           ; loop trough the 8 bytes of the
                                            ; custom character.
        
        lfsr    FSR0, buffer+0

        return



;******************************************************************************
; read_ext_charset: Read extended character set stored in code memory 
;                   (charmap.asm)
;
; Arguments : W= Character set id
; Return    : Character data is stored in buffer+0
;******************************************************************************
read_ext_charset:
        mullw   D'8'                        ; Multiply W by 8

        ltblptr charset                     ; Set table ptr to start of charset
                                            ; table
        
        addff16 PRODL,PRODH,TBLPTRL,TBLPTRH ; Offset table ptr by the result
                                            ; of the multiplication
        
        movlw   D'8'
        movwf   i2

        clrf    EECON1
        bsf     EECON1, EEPGD

loop_read_charset:      
        tblrd*+
        
        movf    TABLAT, W
        xorlw   0xFF
        btfsc   STATUS, Z
        bra     skip_char
        
        movff   TBLPTRL, p_tblptrl
        movff   TBLPTRH, p_tblptrh
        movff   TBLPTRU, p_tblptru
        
        movf    TABLAT, W
        call    read_ext_char

        movff   p_tblptrl, TBLPTRL
        movff   p_tblptrh, TBLPTRH
        movff   p_tblptru, TBLPTRU
        
        movf    i2, W
        sublw   D'8'
        call    lcd_write_cgram

skip_char:
        decfsz  i2
        bra     loop_read_charset

        return




;==============================================================================
;==============================================================================
;
;                                Interrupt handler
;------------------------------------------------------------------------------
interrupts:
        btfsc   PIR1, RCIF
        call   usart_isr
        
        btfsc   INTCON3, INT1IF
        call    int1_isr
        
        btfsc   INTCON, INT0IF
        call    int0_isr
        
        btfsc   PIR1, TMR1IF
        call    tmr1_isr
        
        
        retfie  S                           ; Fast return

;--------------------------------
; int1 : button 1 low-to-high
;--------------------------------
int1_isr:
        

        movlw   'B'
        btfss   bl_state, 6
        call    usart_write_byte
       

        clrf    t_seconds                   ; Reset auto-dim timer
        clrf    t_fsec
        bcf     bl_state, 6                 ; Reset dim flag
        
        bcf     INTCON3, INT1IF
        return

;--------------------------------
; int0 : button 0 low-to-high
;--------------------------------
int0_isr:        
        movlw   'A'
        btfss   bl_state, 6
        call   usart_write_byte

        clrf    t_seconds                   ; Reset auto-dim timer
        clrf    t_fsec
        bcf     bl_state, 6                 ; Reset dim flag
        
        bcf     INTCON, INT0IF
        return


;--------------------------------
; tmr1_isr : Timer 1 overflow
;--------------------------------
tmr1_isr:
        bcf     PIR1, TMR1IF                ; Clear interrupt flag
        
        bsf     PIE1, TMR1IE                ; Re-enable timer1
        movlw   D'60'                       ; 10 hz, 15536 period
        movwf   TMR1H
        movlw   D'176'
        movwf   TMR1L

        incf    t_fsec
        movlw   D'20'
        cpfseq  t_fsec
        bra     check_backlight_state
        
        clrf    t_fsec
        incf    t_seconds

check_backlight_state:

        movf    cfg_lcd_dimdl, W
        cpfslt  t_seconds
        bsf     bl_state, 6
        
        movf    cfg_lcd_dimdl
        btfsc   STATUS, Z
        bcf     bl_state, 6

        movff   cfg_lcd_bl, bl_value
        btfsc   bl_state, 6
        movff   cfg_lcd_bldim, bl_value

        movf    cfg_lcd_brate
        btfsc   STATUS, Z
        bra     no_blink_change

        incf    bl_state, W
        andlw   0x3F
        btfss   STATUS, Z
        incf    bl_state
        
        cpfslt  cfg_lcd_brate
        bra     no_blink_change
        
        movlw   0xC0                        ; Reset blink counter
        andwf   bl_state

        btg     bl_state, 7
no_blink_change:

        btfsc   bl_state, 7
        clrf    bl_value

        movf    CCPR1L, W
        cpfseq  bl_value
        movff   bl_value, CCPR1L
        
        return


;******************************************************************************
;******************************************************************************
;* 
;* For tests on emulator (no bootloader)
;* 
;******************************************************************************
;******************************************************************************
        ORG     0x000
        goto    0x400
        
        ORG     0x008
        goto    0x408

        
;==============================================================================
;==============================================================================
        END
