# Детальное описание кода проекта "Гауссово размытие изображения"

## 1. Структура проекта

```
project/
├── main.c       - Основная логика на C
├── src.s        - Ассемблерная реализация
├── Makefile     - Система сборки
└── start.sh     - Скрипт тестирования
```

## 2. main.c - Основной модуль

### 2.1 Заголовочные файлы
```c
#include <stdio.h>      // Ввод/вывод
#include <stdlib.h>     // Работа с памятью
#include <jpeglib.h>    // JPEG обработка
#include <string.h>     // Работа со строками
#include <stdint.h>     // Типы фиксированной длины
#include <time.h>       // Замер времени
```

### 2.2 Реализация на C
**Прототип функции:**
```c
void gaussian_blur_c(
    uint8_t *temp,       // Временный буфер (+2px по краям)
    uint8_t *output,     // Выходное изображение
    int temp_width,      // Ширина временного буфера
    int temp_height,     // Высота временного буфера
    int width,           // Ширина исходного изображения
    int height           // Высота исходного изображения
);
```

**Алгоритм:**
1. **Ядро Гаусса 3x3:**
   ```c
   const int kernel[3][3] = {
       {1, 2, 1},
       {2, 4, 2},
       {1, 2, 1}
   };
   ```

2. **Трехканальная обработка:**
   ```c
   for (int c = 0; c < 3; c++) {  // R, G, B
       for (int y = 0; y < height; y++) {
           for (int x = 0; x < width; x++) {
   ```

3. **Свертка с ядром:**
   ```c
   for (int ky = -1; ky <= 1; ky++) {
       for (int kx = -1; kx <= 1; kx++) {
           // Обработка границ
           int pos_temp_y = clamp(y + 1 + ky, 0, temp_height-1);
           int pos_temp_x = clamp(x + 1 + kx, 0, temp_width-1);
           
           // Накопление суммы
           sum += pixel * kernel[ky+1][kx+1];
       }
   }
   ```

4. **Нормализация:**
   ```c
   sum = (sum + 8) >> 4;  // Деление на 16 с округлением
   ```

### 2.3 JPEG обработка
**Чтение JPEG:**
```c
void read_jpeg(const char *filename, uint8_t **buffer, int *width, int *height) {
    struct jpeg_decompress_struct cinfo;
    // ...инициализация...
    *buffer = malloc(*width * *height * 3);
    // Построчное чтение:
    while (cinfo.output_scanline < height) {
        row_pointer[0] = *buffer + scanline * width * 3;
        jpeg_read_scanlines(&cinfo, row_pointer, 1);
    }
}
```

**Запись JPEG:**
```c
void write_jpeg(const char *filename, uint8_t *buffer, int width, int height) {
    struct jpeg_compress_struct cinfo;
    // ...настройка параметров...
    jpeg_set_quality(&cinfo, 90, TRUE);
    // Построчная запись:
    while (cinfo.next_scanline < height) {
        row_pointer[0] = buffer + scanline * width * 3;
        jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }
}
```

### 2.4 Основная функция
**Логика работы:**
1. Обработка аргументов командной строки
2. Создание расширенного буфера:
   ```c
   // Добавление 1px границ
   for (int y = -1; y <= height; y++) {
       int src_y = clamp(y, 0, height-1);
       // Аналогично для x
   }
   ```
3. Выбор реализации:
   ```c
   #ifdef USE_C_VERSION
       gaussian_blur_c(...);
   #else
       gaussian_blur_asm(...);
   #endif
   ```
4. Замер производительности:
   ```c
   clock_gettime(CLOCK_MONOTONIC, &start);
   // ...выполнение...
   clock_gettime(CLOCK_MONOTONIC, &end);
   ```

## 3. src.s - Ассемблерная реализация

### 3.1 Структура данных
**Секция .rodata:**
```nasm
kernel:
    db 1, 2, 1    ; Строка 0
    db 2, 4, 2    ; Строка 1
    db 1, 2, 1    ; Строка 2
```

### 3.2 Регистровая схема
| Регистр | Назначение                |
|---------|---------------------------|
| rdi     | Ширина выходного изображения |
| rsi     | temp_width                |
| rdx     | temp_height               |
| rcx     | Канал (0-2)               |
| r8      | Высота выходного изображения |
| r9      | temp buffer               |
| r10     | output buffer             |
| r11     | temp buffer pointer       |

### 3.3 Основные циклы
**Вложенная структура:**
1. Цикл по каналам (R/G/B)
2. Цикл по строкам Y
3. Цикл по столбцам X
4. Цикл по ядру KY (-1..1)
5. Цикл по ядру KX (-1..1)

**Обработка границ:**
```nasm
; Для Y-координаты
lea ecx, [r12 + 1 + r15d]  ; y + 1 + ky
cmp ecx, 0
jl .clamp_low_y
cmp ecx, r9d
jge .clamp_high_y
```

**Вычисление адреса пикселя:**
```nasm
imul ecx, esi      ; y * temp_width
add ecx, edx       ; + x
imul ecx, 3        ; * 3 байта на пиксель
add ecx, ebx       ; + смещение канала
movzx edx, byte [r11 + rcx]
```

**Применение ядра:**
```nasm
; Индекс в ядре
mov ecx, r15d       ; ky
add ecx, 1          ; 0..2
imul ecx, 3         ; смещение строки
add ecx, eax        ; + kx
add ecx, 1          ; 0..2
movzx ecx, byte [kernel + rcx]
```

**Нормализация:**
```nasm
add r14d, 8       ; +8 для округления
shr r14d, 4       ; >>4 (деление на 16)
mov byte [r10 + rcx], r14b
```

## 4. Makefile

### 4.1 Ключевые переменные
```makefile
CC = gcc
AS = nasm
CFLAGS = -Wall -Wextra -g -O2
ASFLAGS = -f elf64
LDFLAGS = -no-pie -lrt -ljpeg
```

### 4.2 Условная компиляция
```makefile
ifeq ($(TARGET),c)
    CFLAGS += -DUSE_C_VERSION
    OBJS = main.o
else
    OBJS = main.o src.o
endif
```

### 4.3 Правила сборки
```makefile
%.o: %.c
    $(CC) $(CFLAGS) -c $<

%.o: %.s
    $(AS) $(ASFLAGS) $< -o $@

$(EXE): $(OBJS)
    $(CC) $(LDFLAGS) $^ -o $@
```

## 5. start.sh

**Логика работы:**
```bash
# Тест C-версий
for opt in O0 O1 O2 O3 Ofast; do
    make clean && make TARGET=c OPT=$opt
    ./bin input.jpg output.jpg
done

# Тест ASM-версии
make clean && make TARGET=asm
./bin input.jpg output.jpg
```