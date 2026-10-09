# Proyecto 3: Batalla Naval
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

*Fecha: 08/10/2026
---

## Introducción
El presente proyecto tiene como objetivo desarrollar un microprocesador de 32 bits basado en un subconjunto de instrucciones RV32I de la arquitectura RISC-V, descrito en SystemVerilog e implementado en una FPGA. La plataforma integra una memoria de programa, una memoria de datos y periféricos mapeados en memoria para la visualización mediante VGA, la lectura de botones, la comunicación UART y el manejo de indicadores visuales y sonoros. La lógica del juego se ejecuta mediante un programa en ensamblador, encargado de gestionar la colocación de barcos, la alternancia de turnos, la validación de disparos y la determinación del ganador.
La interacción se distribuye entre un jugador local, que utiliza los botones de la FPGA y un monitor VGA, y un jugador remoto, que participa mediante una aplicación de computadora conectada por UART. Esta aplicación funciona como una terminal de entrada y salida, mientras que el microprocesador concentra el control de la partida. Cada jugador dispone de un tablero de 8 × 8 casillas y una visualización independiente que mantiene oculta la ubicación de los barcos del oponente.

--- 

## Fundamentación teórica
---

## Presentación de resultados
### Módulo Procesador
Se utilizó un procesor RISCV32I pipeline en este proyecto. Este ejecuta las instrucciones del programa cargado en la ROM y procesa los datos que envía y recibe de los periféricos a través del "Árbitro". Las señales que salen del procesador son "DataAddress_o [31:0]", "DataOut_o [31:0]", "we_o", y la señal que entra es "DataIn_i [31:0]".

### Módulo Árbitro
El módulo Árbitro se compone de un módulo Traductor de Direcciones y un un MUX. El Traductor de Direcciones toma la señal "DataAddress_o [31:0]" y según su valor, selecciona la señal que deja pasar el MUX, por medio de "select_o [2:0]". También el Traductor habilita una señal específica de "Write Enable" para cada periférico, según el "DataAddress", si la señal "we_o" está activa. El MUX envía la señal seleccionada al procesador, con el nombre "DataIn_i".

### Módulo Displays
### Módulo Buzzer
### Módulo Debouncer Botones
### Módulo Periférico UART



### Módulo Periférico VGA

#### Funcionamiento del periférico VGA

El periférico VGA convierte los datos recibidos del procesador, a través del árbitro, en la imagen del tablero del jugador 2 y su panel de información. Sus cinco módulos trabajan como una sola unidad: almacenan el contenido gráfico, determinan el color de cada píxel y generan los sincronismos del monitor. Esta descripción corresponde a la versión base utilizada en los diagramas, anterior a la precarga de pantalla.

##### Integración — `periferico_vga.sv`

Conecta la memoria de video con el controlador y adapta el acceso del procesador. Recibe `addr_i[31:0]`, `wdata_i[31:0]` y la habilitación de escritura `we_vga`; devuelve las lecturas mediante `rdata_o[31:0]`.

Comprueba que la dirección esté dentro del rango asignado y alineada a cuatro bytes. Con la base predeterminada `0x00011000`, obtiene el índice de palabra mediante `(addr_i - BASE_ADDR) >> 2`. Las lecturas son síncronas, con un ciclo de latencia; las direcciones inválidas devuelven cero y no permiten escrituras. El acceso del procesador utiliza `clk_i`, mientras que la generación de video utiliza `clk_25`.

##### Almacenamiento — `memoria_video.sv`

Implementa una RAM de doble puerto de **512 palabras de 32 bits —2 KiB—**, direccionadas internamente con 9 bits. Un puerto permite leer y escribir desde el procesador; el otro proporciona las lecturas del controlador VGA. Al escribir, el puerto del procesador también entrega el dato recién escrito, comportamiento denominado *write-first*.

Cada palabra describe una casilla o celda gráfica:

| Índices de palabra | Contenido |
|---|---|
| 0–63 | Tablero de 8 × 8, ordenado por filas desde la esquina superior izquierda. |
| 64–453 | Panel de 13 columnas × 30 filas: 390 celdas. |
| 454–511 | 58 palabras disponibles sin representación en pantalla. |

El controlador interpreta los siguientes campos:

| Bits | Función |
|---|---|
| `[2:0]` | Color RGB: un bit para rojo, verde y azul, respectivamente. |
| `[9:3]` | Código ASCII de 7 bits. |
| `[10]` | Modo del panel: `0` para bloque de color; `1` para carácter. |
| `[13:11]` | Color de fondo del carácter. |
| `[31:14]` | Se almacenan, pero no intervienen en la imagen. |

##### Generación de imagen — `controlador_vga.sv`

Utiliza contadores horizontal y vertical de 10 bits para recorrer **800 × 525 posiciones totales**, de las cuales **640 × 480 son visibles**. Con el reloj de 25 MHz, genera aproximadamente 59,52 imágenes por segundo y produce los sincronismos horizontal y vertical.

A partir de las coordenadas calcula qué palabra debe consultar: las primeras 432 columnas corresponden al tablero, con casillas de 54 × 60 píxeles; las 208 restantes forman el panel, con celdas de 16 × 16 píxeles. También dibuja la rejilla y selecciona el color de la casilla, del carácter o de su fondo.

Un banco de registros alinea las señales de control con la lectura síncrona de la RAM. Después, otra etapa registra conjuntamente el color y los sincronismos en `screen_o[4:0] = {R, G, B, HS, VS}`. Fuera del área visible, el color permanece negro.

##### Caracteres — `fuente_5x7.sv`

Es una tabla gráfica combinacional que recibe el código ASCII y las coordenadas dentro del carácter. Devuelve un bit que indica si corresponde dibujar el trazo. Contiene patrones de 5 × 7 puntos; el controlador los amplía dentro de celdas de 16 × 16 píxeles.


### Programa del Sistema
Se escribió un programa en lenguaje ensamblador, el cuál es leído por la memoria ROM, para que el procesador lo ejecute. El programa busca ejecutar el juego en 4 etapas: la primera, una etapa de inicial, donde el programa inicializa las señales que se utilizaran, el programa se mantiene en un ciclo infinito hasta que algún jugador accione el botón o switch correspondiente, en este caso el swtich SW1 de la FPGA Nexys 4; la segunda etapa es la etapa de colocación, cada jugador puede colocar 3 barcos de tamaños 2, 3 y 4 casillas que siempre estarán en posición vertical, la partida comienza, únicamente, si ambos jugadores colocaron sus barcos, al momento de colocar los barcos, el programa tiene protecciones en caso de que  se salga del tablero o se intente colocar encima de otro barco.

La tercera etapa, es la encargada de llevar el registro de la partida, el control de turnos, el verificador de golpe, el actualizador de tableros y checa si hay un ganador al finalizar cada jugada. La última etapa, muestra al ganador, actualiza el contador de los 7 segmentos y se mantiene en esta etapa hasta que algún jugador presione el botón para reiniciar, el programa tiene 2 tipos de reinicios, uno parcial y otro completo; el parcial, solo comienza una nueva partida, mientras que el completo reinicia todo el programa y devuelve los contadores a 0.
---

## Análisis de resultados
### Módulo Procesador
### Módulo Árbitro
### Módulo Displays
### Módulo Buzzer
### Módulo Debouncer Botones
### Módulo Periférico UART
### Módulo Periférico VGA
### Programa del Sistema
---

### Conclusión
---

### Referencias
