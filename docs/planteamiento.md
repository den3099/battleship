# Diseño Juego Batalla Naval
**Integrantes**

**Dennis Manuel Arce Alvarez**  
*Escuela de Ingeniería Electrónica*  
*Tecnológico de Costa Rica*  
Carné: 2018151568

**Brayan Díaz Ruiz**  
*Escuela de Ingeniería Electrónica*  
*Tecnológico de Costa Rica*  
Carné: 2018203585

**Joan Franco Sandoval**  
*Escuela de Ingeniería Electrónica*  
*Tecnológico de Costa Rica*  
Carné: 2020248356

**Steven Sancho Orozco**  
*Escuela de Ingeniería Electrónica*  
*Tecnológico de Costa Rica*  
Carné: 2019015506

*Fecha:*
---

## Primer Nivel: Descripción General del Sistema
En este primer nivel se describe la funcionalidad básica del juego, donde el sistema recibe las entradas de los jugadores y el posicionamiento de los barcos, y el sistema saca las señales de video, buzzer y displays.

![Diagrama de Primer Nivel](../img/Nivel_1.jpg)
---

## Segundo Nivel: Arquitectura de Subsistemas
Para el segundo nivel, se diferencian las entradas de los jugadores en botones para el jugador 2 y entradas por medio de un aplicación de PC para el jugador 1. Las entradas del J1 se comunican al sistema por medio comunicación serial con UART. El sistema tiene un procesador que maneja la lógica del juego y un módulo árbitro que comunica los periféricos con el procesador.

![Diagrama de Segundo Nivel](<../img/Nivel 2.jpg>)
---

## Tercer Nivel:
Para el tercer nivel, se especifican el nombre de cada señal que entra y salen de los periféricos y los módulos de cada uno de estos. El microprocesador se plantea con una arquitectura RISCV. El módulo "Árbitro" será el encargado de cuales señales recibe el procesador según la dirección que entre a este módulo. El módulo Displays maneja el control para el LED de estado de la partida y displays de 7 segmentos que permitiran observar el marcador del juego.

El módulo Buzzer emite tonos al inicio de cada etapa de juego y cuando se cumplan ciertas condiciones durante la partida como acertar a un barco, fallo el tiro, hundir un barco, ganar la partida, etc. El módulo UART se encargará de comunicar la aplicación de PC con el sistema, esto por medio de un UART serial. El módulo Periférico VGA, maneja el control de la pantalla y lo que se muestra en esta, no cuenta con lógica del juego, únicamente, tiene el control de como se muestran los datos en pantalla.

![Diagrama de Tercer Nivel](<../img/Diagrama N3.png>)
---

## Cuarto Nivel
### Módulo Procesador
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel Procesador](../img/Procesador_N4.png)

#### b) Objetivo del módulo

Este módulo busca implmentar un procesador pipeline con arquitectura RISCV32I que pueda ser capaz de ejecutar la siguiente lista de instrucciones:

* lw, sw
* sll, slli, srl, srli, sra, srai
* add, and, xor, or, sub
* Addi, andi, xori, ori
* beq, bne, blt, bge
* slt, slti, sltu, sltui
* jal, jalr

El programa que ejecutará el procesador será cargado en la memoria ROM. Este será el encargado de llevar toda la lógica del juego.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `rst_i` | Señal de reset del sistema. |
| `ProgIn_i` | Señal de entrada de instrucciones. |
| `DataIn_i` | Señal de entrada de datos. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `ProgAddress_o` | Señal de dirección de instrucciones. |
| `DataAddress_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de salida de datos. |
| `we_o` | Señal de salida de "Write Enable". |


#### e) Relación con otros módulos

El procesador conecta a los periféricos del sistema las señales "DataAddress_o [31:0]" y "DataOut_o [31:0]", y por medio del módulo "Árbitro" y las señales "DataAddress_o [31:0]" y "we_o" deciden en que periféricos se escribe y cuál es leído según sea la instrucción

#### f) Explicación de funcionamiento

Es un procesador multiciclo segmentado, una instrucción se completa luego de varios ciclos de reloj, y pueden estar ejecutándose varias a la vez. El procesador cuenta con predictor de saltos y unidad de control de "hazards". La memoria RAM está separada del procesador y esta es tomada como un periférico más del sistema completo, es la que en donde se guardarán os datos del programa.

### Módulo Árbitro
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel Arbitro](<../img/Diagrama N4 Arbitro.png>)

#### b) Objetivo del módulo

Este módulo tiene 2 funciones: la primera determinar la señal de "Write Enable" correspondiente a periférico según la dirección que recibe; y la segunda, seleccionar la señal de datos que recibe el procesador desde los periféricos.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `DataAddress_o` | Señal de dirección de datos. |
| `rdata_mem` | Señal de datos leídos desde RAM. |
| `rdata_displays` | Señal de datos leídos de Displays 7 Segmentos. |
| `rdata_buzzer` | Señal de datos leídos desde módulo Buzzer. |
| `rdata_btns` | Señal de datos leídos desde módulo Debouncer. |
| `rdata_uart` | Señal de datos leídos desde módulo UART. |
| `rdata_vga` | Señal de datos leídos desde periférico VGA. |
| `we_o` | Señal de entrada de "Write Enable". |
| `rdata_led` | Señal de datos leídos de LED Estado.

#### d) Salidas

| Entrada | Descripción |
|---|---|
| `DataIn_i` | Señal de salida de datos. |
| `we_mem` | Señal de salida de "Write Enable" para RAM. |
| `we_displays` | Señal de salida de "Write Enable" para módulo Displays. |
| `we_buzzer` | Señal de salida de "Write Enable" para módulo Buzzer. |
| `we_btns` | Señal de salida de "Write Enable" para módulo Debouncer. |
| `we_uart` | Señal de salida de "Write Enable" para módulo UART. |
| `we_vga` | Señal de salida de "Write Enable" para periférico VGA. |

#### e) Relación con otros módulos

Comunica al procesador con los distintos periféricos del sistema, controlando las señales que le llegan.

#### f) Explicación de funcionamiento

Recibe desde el procesador las señales "DataAddress_o [31:0]" y "we_o", y en base a la dirección, envía la señal "select_o [2:0]" hacia el MUX que dejará pasar la señal de datos del periférico que dicta la dirección. Cuando "we_o" está activo, envía la señal de "Write Enable" correspondiente del periférico.

La tabla de verdad 1 describe el comportamiento del traductor de direcciones y la tabla 2 el comportamiento del MUX.

Tabla 1. Tabla de Verdad Traductor de Direcciones.
| DataAddress_o [31:0] | we_o | select_o [2:0] | we_mem | we_displays | we_buzzer | we_btns | we_uart | we_vga | we_led |
|---|---|---|---|---|---|---|---|---|---|
| [0x0000_0000 - 0x0000_1FFF] | 0 | 000 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| [0x0000_0000 - 0x0000_1FFF] | 1 | 000 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0130 | 0 | 001 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0130 | 1 | 001 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0138 | 0 | 110 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0138 | 1 | 110 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| 0x0001_0140 | 0 | 010 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0140 | 1 | 010 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| 0x0001_0120 | 0 | 011 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0120 | 1 | 011 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| 0x0001_0040 | 0 | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0044 | 0 | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0048 | 0 | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0x0001_0040 | 1 | 100 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| 0x0001_0044 | 1 | 100 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| 0x0001_0048 | 1 | 100 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| [0x0001_1000 – 0x0001_17FF] | 0 | 101 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| [0x0001_1000 – 0x0001_17FF] | 1 | 101 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |

Tabla 2. Tabla de Verdad MUX Árbitro
| select_o [2:0] | DataIn_i [31:0] |
|---|---|
| 000 | rdata_mem |
| 001 | rdata_displays |
| 010 | rdata_buzzer |
| 011 | rdata_ btns|
| 100 | rdata_uart |
| 101 | rdata_vga |


### Módulo Displays
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel Displays](../img/Displays_N4.png)

#### b) Objetivo del módulo

Este módulo maneja el los displays 7 segmentos y el LED de Estado de la partida.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `rst_i` | Señal de reset del sistema. |
| `DataAddres_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de entrada de datos. |
| `we_displays` | Señal de entrada de "Write Enable" para Displays 7 Segmentos. |
| `we_led` | Señal de entrada de "Write Enable" para LED Estado. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `rdata_displays` | Señal de datos leídos de Displays 7 Segmentos. |
| `rdata_led` | Señal de datos leídos de LED Estado. |

#### e) Relación con otros módulos

El procesador envía el marcador de la partida que el módulo de los diplays 7 segmentos procesa para mostrarlos, y también el módulo de LED de Estado cambia el color de la bombilla según la etapa actual del juego.

#### f) Explicación de funcionamiento

El módulo recibe el valor del contador de cada jugador, el cuál es procesado para que sean mostrado en números de 2 dígitos para cada jugador. Este módulo también maneja el cambio de color del LED de Estado según el momento de la partida en que se encuentre, este puede cambiar a 3 colores.

### Módulo Buzzer
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel Buzzer](../img/Buzzer_N4.png)

#### b) Objetivo del módulo

El módulo buzzer agrega retroalimentación sonora al sistema.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `rst_i` | Señal de reset del sistema. |
| `DataAddres_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de entrada de datos. |
| `we_buzzer` | Señal de entrada de "Write Enable" para módulo Buzzer. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `rdata_buzzer` | Señal de datos leídos desde módulo Buzzer. |

#### e) Relación con otros módulos

El procesador indica cuando debe activarse el buzzer y que sonido debe emitir.

#### f) Explicación de funcionamiento
El módulo buzzer tiene 6 tonos diferentes que se ejecutan según se cumpla la condición. Estos tonos son: "silencio", cuando no se realiza ninguna acción durante la partida o cuando termina de emitirse otro tono; "impacto", cuando se logra golpear un barco oponente; "fallo", cuando no se logra acertar algún barco; "barco hundido", cuando se golpea, totalmente, un barco; "colocación inválida", cuando se intenta colocar un barco en un lugar no permitido; y, "victoria", cuando un jugador logra derribar todos los barcos del otro.

### Módulo Debouncer Botones
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel Botones](../img/Botones_N4.png)

#### b) Objetivo del módulo

Este módulo aplica un sistema antirebotes para los botones físicos del jugador.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `rst_i` | Señal de reset del sistema. |
| `DataAddres_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de entrada de datos. |
| `we_btns` | Señal de entrada de "Write Enable" para módulo Debouncer. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `rdata_btns` | Señal de datos leídos desde módulo Debouncer. |

#### e) Relación con otros módulos

El procesador recibe las entradas de los botones y realiza las acciones correspondientes, desde mover el cursor en la pantalla VGA hasta reiniciar o comenzar el juego.

#### f) Explicación de funcionamiento
Se utilizó un sincronizador de 2 etapas para evitar el rebote físico de los botones al ser presionados.

### Módulo Periférico UART
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel de la UART](<../img/UART_4Nivel.png>)

#### b) Objetivo del módulo
#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `rst_i` | Señal de reset del sistema. |
| `DataAddres_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de entrada de datos. |
| `we_uart` | Señal de entrada de "Write Enable" para módulo UART. |
| `rx_fisico` | Señal RX desde PC a UART. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `rdata_pc` | Señal de datos leídos desde módulo UART. |
| `tx_fisico` | Señal TX desde UART a PC. |

#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Periférico VGA
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel VGA](<../img/Nvl 4 Periferico vga.png>)

#### b) Objetivo del módulo

Permitir la comunicación entre el procesador y la pantalla VGA mediante una memoria de video mapeada en memoria. El módulo permite almacenar, leer y modificar información gráfica, además de generar las señales necesarias para visualizarla en una resolución de 640 × 480 píxeles.

#### c) Entradas

| Entrada | Descripción |
|---|---|
| `clk_i` | Señal de reloj del sistema. |
| `clk_25` | Señal de reloj de 25 MHz. |
| `DataAddres_o` | Señal de dirección de datos. |
| `DataOut_o` | Señal de entrada de datos. |
| `we_vga` | Señal de entrada de "Write Enable" para periférico VGA. |

#### d) Salidas

| Salida | Descripción |
|---|---|
| `rdata_vga` | Señal de datos leídos desde periférico VGA. |
| `screen_o` | Señal de color y posicionamiento de los pixeles en la pantalla. |

#### e) Relación con otros módulos

El periférico VGA se comunica con el procesador para recibir direcciones, datos y señales de escritura. Internamente, utiliza el módulo memoria_video para almacenar la información gráfica y el módulo controlador_vga para generar las señales RGB y los sincronismos de pantalla. Además, emplea fuente_5x7 para representar caracteres y reset_sincrono para controlar el reinicio de los distintos dominios de reloj.

#### f) Explicación de funcionamiento
Explicación del funcionamiento del periférico VGA
El periférico VGA permite al procesador leer y modificar la información gráfica mediante una memoria de video mapeada en memoria.
Primero, se recibe la dirección addr_i[31:0], se calcula su desplazamiento respecto a BASE_ADDR y se valida que pertenezca al rango de 2048 bytes y esté alineada a 32 bits.
Si la dirección es válida, se habilita el acceso a la memoria de video de 512 palabras de 32 bits. El procesador puede escribir datos mediante we_vga y wdata_i, o leerlos mediante rdata_o.
De forma independiente, el controlador VGA, utilizando un reloj de 25 MHz, consulta continuamente la memoria de video y genera las señales RGB y los sincronismos horizontal y vertical para mostrar una imagen de 640 × 480 píxeles.
Finalmente, los cambios realizados por el procesador en la memoria se reflejan en la pantalla durante el barrido VGA, permitiendo actualizar los elementos gráficos sin interrumpir la generación de video.
