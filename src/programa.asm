.text
.globl _start

    # ------------------------------------------
    # INICIALIZACIÓN DEL SISTEMA
    # ------------------------------------------
    # La UART usa subrutinas que guardan ra en la pila. RAM disponible:
    # 0x2000..0x2FFF; sp apunta al extremo superior (crece hacia abajo).
    addi sp, zero, 3
    slli sp, sp, 12

    # Apaga Buzzer (0x00010140)
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0140
    sw zero, 0(t0)

    # Enciende LED Estado (0x00010138)
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0138
    sw zero, 0(t0)
    
    # Coloca turno 1 en la memoria RAM (0x00002000)
    addi t0, zero, 2
    slli t0, t0, 12
    addi t1, zero, 1
    sw t1, 0(t0)

    # Inicializa s4 para el antirrebote de los botones
    addi s4, zero, 0

esperar_inicio:
    # ------------------------------------------
    # PANTALLA DE INICIO
    # ------------------------------------------
    # Drena tramas de sondeo de la PC mientras espera SW0. El UART solo
    # almacena un byte, asi que se debe consumir completa cualquier trama.
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 64
    lw t5, 0(t6)
    andi t5, t5, 8
    beq t5, zero, esperar_inicio_botones
    jal recibir_trama_uart
    j esperar_inicio

esperar_inicio_botones:
    # Lee botones (0x00010120)
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)
    
    # Detector de Flanco
    xor t2, t1, s4
    and t2, t2, t1
    add s4, zero, t1
    beq t2, zero, esperar_inicio

    # Revisa si el botón presionado fue "SW0" (Bit 4 = 16)
    andi t3, t2, 16
    beq t3, zero, esperar_inicio  # Si se presiona otro botón distinto, lo ignora y cicla
    
    # Notifica a la PC que inicia el juego (0x11 = PLACEMENT_START)
    addi a0, zero, 0x11     # TYPE
    addi a1, zero, 0        # D0
    addi a2, zero, 0        # D1
    addi a3, zero, 0        # D2
    addi a4, zero, 0        # D3
    jal enviar_trama_uart

fase_colocacion:
    # ------------------------------------------
    # INICIALIZACIÓN DE VARIABLES DE COLOCACIÓN
    # ------------------------------------------
    addi s1, zero, 2        # s1 = Tamaño barco J1
    addi s3, zero, 2        # s3 = Tamaño barco J2
    addi s4, zero, 0        # s4 = Estado botones
    addi s5, zero, 0        # s5 = Posición del cursor del J1
    
    # s0 = Direccion Base VGA (0x00011000)
    addi s0, zero, 17
    slli s0, s0, 12
    
    # s6 = Direccion Base J1 RAM (0x00002100)
    addi s6, zero, 2
    slli s6, s6, 12
    addi s6, s6, 256

    # s2 = Direccion Base J2 RAM (0x00002200)
    addi s2, zero, 2
    slli s2, s2, 12
    addi s2, s2, 512

loop_colocacion:
    # Chequeo de reinicio
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288        # Registro de botones
    lw t1, 0(t0)
    andi t3, t1, 64         # Revisa si se presiona el botón de reinicio (Bit 6)
    bne t3, zero, reset_completo

    # Condición de salida
    addi t0, zero, 5
    bne s1, t0, check_j1
    bne s3, t0, check_j2
    j transicion_partida    # Cuando ambos jugadores terminaron, prepara la pantalla

    # ------------------------------------------
    # COLOCACION J1
    # ------------------------------------------
check_j1:
    addi t0, zero, 5
    beq s1, t0, check_j2

    # Direccion Botones (0x00010120)
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)            
    
    # Detector de Flanco
    xor t2, t1, s4
    and t2, t2, t1
    add s4, zero, t1        
    beq t2, zero, check_j2  

    # Bit 5 - SW1 (Confirmar)
    andi t3, t2, 32
    bne t3, zero, j1_confirm
    
    # Bit 0 - BTNU (Arriba)
    andi t3, t2, 1
    beq t3, zero, check_down
    addi t4, zero, 8
    blt s5, t4, check_down    
    sub s5, s5, t4

check_down:
    # Bit 1 - BTND (Abajo)
    andi t3, t2, 2
    beq t3, zero, check_left
    addi t4, zero, 56
    bge s5, t4, check_left    
    addi s5, s5, 8

check_left:
    # Bit 2 - BTNL (Izquierda)
    andi t3, t2, 4
    beq t3, zero, check_right
    andi t4, s5, 7          
    beq t4, zero, check_right 
    addi t4, zero, 1
    sub s5, s5, t4

check_right:
    # Bit 3 - BTNR (Derecha)
    andi t3, t2, 8
    beq t3, zero, end_nav
    andi t4, s5, 7          
    addi t5, zero, 7
    beq t4, t5, end_nav     
    addi t4, zero, 1
    addi s5, s5, 1

end_nav:
    j check_j2              

j1_confirm:
    add a0, zero, s5        
    
    # Validar Límites Verticales
    srli t3, a0, 3          # Fila inicial (índice / 8)
    add t4, t3, s1          # Fila + tamaño
    addi t5, zero, 8
    blt t5, t4, j1_error_colision 

    # Validar Colisiones en RAM de J1
    addi t3, zero, 0

j1_check_col:
    beq t3, s1, j1_place
    slli t4, t3, 3
    add t4, t4, a0
    slli t4, t4, 2
    add t4, t4, s6          # Chequea colisiones en la RAM (s6)
    lw t5, 0(t4)
    bne t5, zero, j1_error_colision  
    addi t3, t3, 1
    j j1_check_col

j1_error_colision:
    # Activa Buzzer para Colocación inválida
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0140
    addi t1, zero, 4
    sw t1, 0(t0)
    j check_j2

j1_place:
    addi t3, zero, 0
    addi t6, zero, 3        # Color cyan para mostrar barcos durante colocacion

j1_place_loop:
    beq t3, s1, j1_done
    slli t4, t3, 3
    add t4, t4, a0
    slli t4, t4, 2
    
    # Guarda en VGA (s0) para verlo
    add t5, t4, s0
    sw t6, 0(t5)            
    
    # Guarda en RAM de J1 (s6) para almacenar el dato real
    add t5, t4, s6
    addi t6, s1, -1         # ID interno: 1, 2 o 3
    sw t6, 0(t5)
    addi t6, zero, 3        # Restaura el color para la siguiente celda

    addi t3, t3, 1
    j j1_place_loop

j1_done:
    addi s1, s1, 1          
    j check_j2

    # ------------------------------------------
    # COLOCACION J2
    # ------------------------------------------
check_j2:
    addi t0, zero, 5
    beq s3, t0, fin_loop

    # La UART no tiene FIFO: solo entrar al parser si hay un byte pendiente.
    # ESTADO[3] = RX_VALID. Asi J1 puede seguir colocando sin bloquearse.
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 64
    lw t5, 0(t6)
    andi t5, t5, 8
    beq t5, zero, fin_loop

    jal recibir_trama_uart  

    # PLACE: D0=ID, D1=fila, D2=columna, D3=orientacion (0=H, 1=V).
    addi t0, zero, 0x01
    bne a0, t0, fin_loop

    # El programa espera IDs secuenciales: 0/tamano 2, 1/tamano 3, 2/tamano 4.
    addi t0, s3, -2
    bne a1, t0, j2_error_id
    sltiu t0, a2, 8
    beq t0, zero, j2_error_bounds
    sltiu t0, a3, 8
    beq t0, zero, j2_error_bounds
    sltiu t0, a4, 2
    beq t0, zero, j2_error_id

    # El barco horizontal crece en columnas; el vertical, en filas.
    beq a4, zero, j2_check_horizontal_bounds
    add t4, a2, s3
    addi t5, zero, 8
    blt t5, t4, j2_error_bounds
    j j2_bounds_ok
j2_check_horizontal_bounds:
    add t4, a3, s3
    addi t5, zero, 8
    blt t5, t4, j2_error_bounds
j2_bounds_ok:
    slli t0, a2, 3
    add t0, t0, a3          # indice base = fila*8 + columna

    # Valida cada celda antes de escribir para no dejar colocaciones parciales.
    addi t3, zero, 0
j2_check_col:
    beq t3, s3, j2_place
    beq a4, zero, j2_check_horizontal_cell
    slli t4, t3, 3
    j j2_check_cell_offset
j2_check_horizontal_cell:
    add t4, t3, zero
j2_check_cell_offset:
    add t4, t4, t0
    slli t4, t4, 2
    add t4, t4, s2
    lw t5, 0(t4)
    bne t5, zero, j2_error_overlap
    addi t3, t3, 1
    j j2_check_col

j2_place:
    addi t3, zero, 0
    addi t6, s3, -1         # ID interno del barco: 1, 2 o 3

j2_place_loop:
    beq t3, s3, j2_done
    beq a4, zero, j2_place_horizontal_cell
    slli t4, t3, 3
j2_place_cell_offset:
    add t4, t4, t0
    slli t4, t4, 2
    add t4, t4, s2
    sw t6, 0(t4)
    addi t3, t3, 1
    j j2_place_loop
j2_place_horizontal_cell:
    add t4, t3, zero
    j j2_place_cell_offset
    
j2_done:
    addi a0, zero, 0x12
    # PLACE_ACK: D0=ID, D1=aceptada, D2=motivo, D3=reservado.
    addi a1, a1, 0
    addi a2, zero, 1
    addi a3, zero, 0
    addi a4, zero, 0
    jal enviar_trama_uart

    addi s3, s3, 1          
    j fin_loop

j2_error:
    # Buzzer Error
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0140
    addi t1, zero, 4
    sw t1, 0(t0)

    # Aviso a PC
    addi a0, zero, 0x12
    # a1 conserva el ID; a2=0 indica rechazo y a3 contiene el motivo.
    addi a2, zero, 0
    addi a4, zero, 0
    jal enviar_trama_uart

    j fin_loop

j2_error_overlap:
    addi a3, zero, 1
    j j2_error

j2_error_bounds:
    addi a3, zero, 2
    j j2_error

j2_error_id:
    addi a3, zero, 3
    j j2_error

fin_loop:
    j loop_colocacion

# ==========================================
# TRANSICIÓN A PARTIDA
# ==========================================
transicion_partida:
    # Cambia LED de Estado
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0138
    addi t1, zero, 1
    sw t1, 0(t0)

    # Carga tablero de J2 en la pantalla VGA
    # s0 = Dirección Base VGA (0x00011000)
    addi s0, zero, 17
    slli s0, s0, 12

    # s2 = Dirección Base J2 RAM (0x00002200)
    addi s2, zero, 2
    slli s2, s2, 12
    addi s2, s2, 512

    addi t1, zero, 0          # Índice inicial = 0
    addi t2, zero, 64         # 64 casillas del tablero
    
cargar_vga_rival_loop:
    beq t1, t2, f_init_batalla
    slli t3, t1, 2
    
    # Lee de la RAM de J2
    add t4, t3, s2
    lw t5, 0(t4)
    
    # El framebuffer marca cualquier barco en cyan; la RAM conserva su ID.
    beq t5, zero, cargar_vga_escribir
    addi t5, zero, 3
cargar_vga_escribir:
    # Escribe en la VGA
    add t6, t3, s0
    sw t5, 0(t6)
    
    addi t1, t1, 1
    j cargar_vga_rival_loop

f_init_batalla:
    # Avisa a la PC que inicia la partida (0x13 = BATTLE_START)
    addi a0, zero, 0x13
    addi a1, zero, 0
    addi a2, zero, 0
    addi a3, zero, 0
    addi a4, zero, 0
    jal enviar_trama_uart

fase_partida:
    # Chequeo de reinicio
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)
    andi t3, t1, 64         # Revisa botón de reinicio (Bit 6)
    bne t3, zero, reset_completo

    # ------------------------------------------
    # EVALUA DE QUIEN ES EL TURNO
    # ------------------------------------------
    addi t0, zero, 2
    slli t0, t0, 12         
    lw t1, 0(t0)

    # Avisa a la PC de quien es el turno (0x14 = TURN)
    addi a0, zero, 0x14
    add a1, zero, t1        # a1 = 1 (J1) o 2 (J2)
    addi a2, zero, 0
    addi a3, zero, 0
    addi a4, zero, 0
    jal enviar_trama_uart            
    
    addi t2, zero, 1
    beq t1, t2, f_turno_j1    
    j f_turno_j2              

# ------------------------------------------
# TURNO J1
# ------------------------------------------
f_turno_j1:
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)
    
    xor t2, t1, s4
    and t2, t2, t1
    add s4, zero, t1
    beq t2, zero, f_fin_j1

    andi t3, t2, 32
    bne t3, zero, f_j1_shoot

    andi t3, t2, 1
    beq t3, zero, f_j1_down
    addi t4, zero, 8
    blt s5, t4, f_j1_down
    sub s5, s5, t4

f_j1_down:
    andi t3, t2, 2
    beq t3, zero, f_j1_left
    addi t4, zero, 56
    bge s5, t4, f_j1_left
    addi s5, s5, 8

f_j1_left:
    andi t3, t2, 4
    beq t3, zero, f_j1_right
    andi t4, s5, 7
    beq t4, zero, f_j1_right
    addi t4, zero, 1
    sub s5, s5, t4

f_j1_right:
    andi t3, t2, 8
    beq t3, zero, f_fin_j1
    andi t4, s5, 7
    addi t5, zero, 7
    beq t4, t5, f_fin_j1
    addi t4, zero, 1
    addi s5, s5, 1

f_fin_j1:
    j fase_partida

f_j1_shoot:
    add a0, zero, s5
    srli s10, a0, 3          # conserva fila y columna durante el conteo
    andi s11, a0, 7
    
    # Lee Tablero de J2 en RAM (Base 0x2200)
    addi t0, zero, 2
    slli t0, t0, 12
    addi t0, t0, 512
    slli t1, a0, 2
    add t0, t0, t1          
    lw t1, 0(t0)
    
    beq t1, zero, f_j1_miss
    sltiu t2, t1, 4
    bne t2, zero, f_j1_hit
    j fase_partida            

f_j1_hit:
    add s6, zero, t1         # ID del barco alcanzado (1..3)
    addi t2, t1, 3           # ID alcanzado: 4..6
    sw t2, 0(t0)

    # Hundimiento exacto: busca si queda alguna celda viva con el mismo ID.
    addi s2, zero, 2
    slli s2, s2, 12
    addi s2, s2, 512         # Base del tablero J2
    addi t3, zero, 0
buscar_vivo_j1:
    addi t5, zero, 64
    beq t3, t5, hundido_j1
    slli t4, t3, 2
    add t4, t4, s2
    lw t5, 0(t4)
    beq t5, s6, vivo_j1
    addi t3, t3, 1
    j buscar_vivo_j1

vivo_j1:
    addi s8, zero, 1
    addi t4, zero, 1        # Buzzer impacto
    j actualizar_vga_j1

hundido_j1:
    # Cuenta impactos (celdas 4..6); nueve impactos terminan la partida.
    addi t3, zero, 0
    addi t4, zero, 0
contar_impactos_j1:
    addi t5, zero, 64
    beq t3, t5, evaluar_fin_j1
    slli t5, t3, 2
    add t5, t5, s2
    lw t6, 0(t5)
    sltiu t5, t6, 4
    bne t5, zero, siguiente_impacto_j1
    sltiu t5, t6, 7
    beq t5, zero, siguiente_impacto_j1
    addi t4, t4, 1
siguiente_impacto_j1:
    addi t3, t3, 1
    j contar_impactos_j1

evaluar_fin_j1:
    addi t5, zero, 9
    beq t4, t5, win_j1_directo
    addi s8, zero, 2
    addi t4, zero, 3        # Buzzer barco hundido

actualizar_vga_j1:
    addi t2, zero, 2        # Color VGA de impacto
    addi t3, zero, 1
    slli t3, t3, 16
    addi t3, t3, 0x0140
    sw t4, 0(t3)
    j f_j1_update

win_j1_directo:
    addi s7, zero, 1
    addi s9, zero, 3          
    slli s9, s9, 2            
    addi s8, zero, 2
    addi t2, zero, 2          # Color VGA de impacto
    # Reporta tambien el disparo ganador antes de GAME_OVER.
    addi t0, zero, 17
    slli t0, t0, 12
    slli t1, a0, 2
    add t0, t0, t1
    sw t2, 0(t0)
    addi a0, zero, 0x16
    add a1, zero, s10
    add a2, zero, s11
    add a3, zero, s8
    addi a4, zero, 0
    jal enviar_trama_uart
    j fase_fin

f_j1_miss:
    addi t3, zero, 7          # Marca de fallo en RAM
    sw t3, 0(t0)
    addi t2, zero, 4          # 4 = Rojo en VGA
    addi s8, zero, 0          # Resultado = 0 (Fallo)

    # Activa Buzzer Fallo
    addi t3, zero, 1
    slli t3, t3, 16
    addi t3, t3, 0x0140
    addi t4, zero, 2
    sw t4, 0(t3)

f_j1_update:
    # Pinta disparo en Tablero VGA
    addi t0, zero, 17
    slli t0, t0, 12
    slli t1, a0, 2            
    add t0, t0, t1          
    sw t2, 0(t0)              
    
    # Avisa a PC del disparo (0x16 = SHOT_RECEIVED)
    addi a0, zero, 0x16
    add a1, zero, s10       # Fila del disparo
    add a2, zero, s11       # Columna del disparo
    add a3, zero, s8        # Resultado
    addi a4, zero, 0
    jal enviar_trama_uart

    # Cede turno a J2
    addi t0, zero, 2
    slli t0, t0, 12         
    addi t1, zero, 2        
    sw t1, 0(t0)            
    j fase_partida

# ------------------------------------------
# TURNO J2
# ------------------------------------------
f_turno_j2:
    # Espera el disparo de la PC
    jal recibir_trama_uart

    # a0 debe ser 0x02 (SHOT)
    addi t0, zero, 0x02
    bne a0, t0, f_turno_j2

    # Convierte fila y columna a indice: (Fila * 8) + Columna
    sltiu t3, a1, 8
    beq t3, zero, fase_partida
    sltiu t3, a2, 8
    beq t3, zero, fase_partida
    slli t0, a1, 3
    add t0, t0, a2          # t0 = Índice

    # Guarda fila y columna temporalmente
    add s10, zero, a1
    add s11, zero, a2

    # Lee el Tablero de J1 en la RAM (Base 0x00002100)
    addi t1, zero, 2
    slli t1, t1, 12
    addi t1, t1, 256
    slli t2, t0, 2
    add t1, t1, t2
    lw t2, 0(t1)

    beq t2, zero, f_j2_miss
    sltiu t3, t2, 4
    bne t3, zero, f_j2_hit
    j fase_partida

f_j2_hit:
    add s6, zero, t2         # ID del barco alcanzado (1..3)
    addi t2, t2, 3           # ID alcanzado: 4..6
    sw t2, 0(t1)
    addi s2, zero, 2
    slli s2, s2, 12
    addi s2, s2, 256         # Base del tablero J1
    addi t3, zero, 0
buscar_vivo_j2:
    addi t5, zero, 64
    beq t3, t5, hundido_j2
    slli t4, t3, 2
    add t4, t4, s2
    lw t5, 0(t4)
    beq t5, s6, vivo_j2
    addi t3, t3, 1
    j buscar_vivo_j2

vivo_j2:
    addi s8, zero, 1
    addi t4, zero, 1        # Buzzer impacto
    j actualizar_buzzer_j2

hundido_j2:
    addi t3, zero, 0
    addi t4, zero, 0
contar_impactos_j2:
    addi t5, zero, 64
    beq t3, t5, evaluar_fin_j2
    slli t5, t3, 2
    add t5, t5, s2
    lw t6, 0(t5)
    sltiu t5, t6, 4
    bne t5, zero, siguiente_impacto_j2
    sltiu t5, t6, 7
    beq t5, zero, siguiente_impacto_j2
    addi t4, t4, 1
siguiente_impacto_j2:
    addi t3, t3, 1
    j contar_impactos_j2

evaluar_fin_j2:
    addi t5, zero, 9
    beq t4, t5, win_j2_directo
    addi s8, zero, 2
    addi t4, zero, 3        # Buzzer barco hundido

actualizar_buzzer_j2:
    addi t3, zero, 1
    slli t3, t3, 16
    addi t3, t3, 0x0140
    sw t4, 0(t3)
    j f_j2_update

win_j2_directo:
    addi s7, zero, 2
    addi s9, zero, 3
    addi s8, zero, 2
    addi a0, zero, 0x15
    add a1, zero, s10
    add a2, zero, s11
    add a3, zero, s8
    addi a4, zero, 0
    jal enviar_trama_uart
    j fase_fin

f_j2_miss:
    addi t3, zero, 7
    sw t3, 0(t1)             # Marca de fallo en RAM
    addi s8, zero, 0          # Fallo

    # Activa Buzzer Fallo
    addi t3, zero, 1
    slli t3, t3, 16
    addi t3, t3, 0x0140
    addi t4, zero, 2
    sw t4, 0(t3)

f_j2_update:
    # Notifica a la PC el resultado del dispatro (0x15 = SHOT_RESULT)
    addi a0, zero, 0x15
    add a1, zero, s10       # Fila
    add a2, zero, s11       # Columna
    add a3, zero, s8        # Resultado
    addi a4, zero, 0
    jal enviar_trama_uart

    # Cede turno a J1
    addi t0, zero, 2
    slli t0, t0, 12         
    addi t1, zero, 1        
    sw t1, 0(t0)            
    j fase_partida

# ==========================================
# FASE FINAL
# ==========================================
fase_fin:
    # Cambia LED de Estado
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0138
    addi t1, zero, 2
    sw t1, 0(t0)

    # Activa Buzzer Victoria
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0140
    addi t1, zero, 5
    sw t1, 0(t0)

    # Notifica a la PC el fin del juego (0x17 = GAME_OVER)
    addi a0, zero, 0x17
    add a1, zero, s7
    addi a2, zero, 0          # estadisticas de disparos no implementadas
    addi a3, zero, 0
    add a4, zero, s9
    jal enviar_trama_uart

    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 312
    addi t1, zero, 4
    sw t1, 0(t0)

    addi t0, zero, 2
    slli t0, t0, 12
    
    addi t2, zero, 1
    beq a1, t2, inc_j1
    
    lw t1, 8(t0)
    addi t1, t1, 1
    sw t1, 8(t0)
    j update_disp
    
inc_j1:
    lw t1, 4(t0)
    addi t1, t1, 1
    sw t1, 4(t0)

update_disp:
    lw t1, 4(t0)        # Victorias J1 (bits [7:0])
    lw t2, 8(t0)        # Victorias J2 (bits [15:8])
    slli t2, t2, 8
    or t1, t1, t2
    
    addi t0, zero, 1    
    slli t0, t0, 16     
    addi t0, t0, 304
    sw t1, 0(t0)        # Envía al Display de 7 Segmentos (0x00010130)

esperar_reset:
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)
    
    xor t2, t1, s4
    and t2, t2, t1
    add s4, zero, t1
    beq t2, zero, esperar_reset

    # Bit 4 (SW0 / Reinicio rápido) o Bit 6 (Reinicio completo)
    andi t3, t2, 16
    bne t3, zero, limpiar_tableros
    andi t3, t2, 64
    bne t3, zero, reset_completo

    j esperar_reset

reset_completo:
    addi t0, zero, 2
    slli t0, t0, 12
    sw zero, 4(t0)
    sw zero, 8(t0)

    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 304
    sw zero, 0(t0)

limpiar_tableros:
    # Cambia LED de Estado a Estado Inicial
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 0x0138
    sw zero, 0(t0)

    # Limpia memoria VGA (Monitor)
    addi t0, zero, 17
    slli t0, t0, 12
    addi t1, zero, 0          
    addi t2, zero, 64         
    
loop_limpiar_vga:
    beq t1, t2, init_limpiar_ram
    slli t3, t1, 2
    add t3, t3, t0
    sw zero, 0(t3)
    addi t1, t1, 1
    j loop_limpiar_vga

init_limpiar_ram:
    # Limpia RAM J1 y RAM J2 (128 casillas desde 0x2100)
    addi t0, zero, 2
    slli t0, t0, 12
    addi t0, t0, 256
    addi t1, zero, 0          
    addi t2, zero, 128        
    
loop_limpiar_ram:
    beq t1, t2, finalizar_reinicio
    slli t3, t1, 2
    add t3, t3, t0
    sw zero, 0(t3)            
    addi t1, t1, 1
    j loop_limpiar_ram

finalizar_reinicio:
    # Espera a que suelten BTN_RST para no reiniciar en cada vuelta.
esperar_liberacion_reset:
    addi t0, zero, 1
    slli t0, t0, 16
    addi t0, t0, 288
    lw t1, 0(t0)
    andi t2, t1, 64
    bne t2, zero, esperar_liberacion_reset
    add s4, zero, zero

    addi t0, zero, 2
    slli t0, t0, 12
    addi t1, zero, 1
    sw t1, 0(t0)

    # Sincroniza la interfaz de PC con la nueva fase de colocacion.
    addi a0, zero, 0x11
    addi a1, zero, 0
    addi a2, zero, 0
    addi a3, zero, 0
    addi a4, zero, 0
    jal enviar_trama_uart
    j fase_colocacion

# ==============================================================================
# SUBRUTINAS DE COMUNICACIÓN UART (Protocolo 7 Bytes)
# ==============================================================================

enviar_trama_uart:
    addi sp, sp, -4
    sw ra, 0(sp)

    xor t0, a0, a1
    xor t0, t0, a2
    xor t0, t0, a3
    xor t0, t0, a4      

    addi a5, zero, 0xAA
    jal uart_tx_byte
    add a5, zero, a0
    jal uart_tx_byte
    add a5, zero, a1
    jal uart_tx_byte
    add a5, zero, a2
    jal uart_tx_byte
    add a5, zero, a3
    jal uart_tx_byte
    add a5, zero, a4
    jal uart_tx_byte
    add a5, zero, t0
    jal uart_tx_byte

    lw ra, 0(sp)
    addi sp, sp, 4
    ret

uart_tx_byte:
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 64  

wait_tx:
    lw t5, 0(t6)
    andi t5, t5, 1      # ESTADO[0] = TX ocupado
    bne t5, zero, wait_tx
    
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 68     
    sw a5, 0(t6)
    ret

recibir_trama_uart:
    addi sp, sp, -4
    sw ra, 0(sp)

wait_sof:
    jal uart_rx_byte
    addi t1, zero, 0xAA
    bne a5, t1, wait_sof 

    jal uart_rx_byte
    add t0, zero, a5     
    jal uart_rx_byte
    add t1, zero, a5     
    jal uart_rx_byte
    add t2, zero, a5     
    jal uart_rx_byte
    add t3, zero, a5     
    jal uart_rx_byte
    add t4, zero, a5     
    jal uart_rx_byte
    add t5, zero, a5     

    xor t6, t0, t1
    xor t6, t6, t2
    xor t6, t6, t3
    xor t6, t6, t4

    bne t6, t5, wait_sof 

    add a0, zero, t0
    add a1, zero, t1
    add a2, zero, t2
    add a3, zero, t3
    add a4, zero, t4

    lw ra, 0(sp)
    addi sp, sp, 4
    ret

uart_rx_byte:
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 64    

wait_rx:
    lw t5, 0(t6)    
    andi t5, t5, 8      # ESTADO[3] = RX_VALID
    beq t5, zero, wait_rx
    
    addi t6, zero, 1
    slli t6, t6, 16
    addi t6, t6, 72     
    lw a5, 0(t6)
    ret
