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
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Árbitro
#### a) Diagrama / Diseño
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Displays
#### a) Diagrama / Diseño
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Buzzer
#### a) Diagrama / Diseño
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Debouncer Botones
#### a) Diagrama / Diseño
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Periférico UART
#### a) Diagrama / Diseño

![Diagrama de Cuarto Nivel de la UART](<../img/UART_nivel_4.png>)

#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento

### Módulo Periférico VGA
#### a) Diagrama / Diseño
#### b) Objetivo del módulo
#### c) Entradas
#### d) Salidas
#### e) Relación con otros módulos
#### f) Explicación de funcionamiento
