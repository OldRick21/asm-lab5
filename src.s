section .rodata
; Gaussian kernel 3x3 (normalized by dividing by 16)
; Kernel structure:
; [1, 2, 1]
; [2, 4, 2]
; [1, 2, 1]
kernel:
    db 1, 2, 1
    db 2, 4, 2
    db 1, 2, 1

section .text
global gaussian_blur_asm

; Gaussian blur function
; Arguments:
;   rdi - temporary buffer pointer
;   rsi - output buffer pointer
;   rdx - temp_width
;   rcx - temp_height
;   r8  - width
;   r9  - height
gaussian_blur_asm:
    push rbp
    mov rbp, rsp
    push rbx                ; Сохраняем используемые регистры
    push r12
    push r13
    push r14
    push r15
    push r10

    ; Переназначаем аргументы для удобства
    mov r10, rsi            ; r10 = output buffer
    mov rsi, rdx            ; rsi = temp_width
    mov r11, rdi            ; r11 = temp buffer
    mov rdi, r8             ; rdi = width
    mov r8, r9              ; r8 = height
    mov r9, rcx             ; r9 = temp_height

    xor ebx, ebx            ; Инициализация счетчика каналов (c = 0)

; Внешний цикл по каналам (R, G, B)
.loop_channels:
    cmp ebx, 3              ; Проверяем все 3 канала
    jge .end_loop_channels

    xor r12, r12            ; Счетчик строк (y = 0)

; Цикл по строкам изображения
.loop_y:
    cmp r12, r8             ; Сравниваем с высотой изображения
    jge .end_loop_y

    xor r13, r13            ; Счетчик столбцов (x = 0)

; Цикл по столбцам изображения
.loop_x:
    cmp r13, rdi            ; Сравниваем с шириной изображения
    jge .end_loop_x

    xor r14d, r14d          ; Обнуляем сумму (sum = 0)

    mov r15d, -1            ; Счетчик строк ядра (ky = -1)

; Цикл по строкам ядра (ky = -1, 0, +1)
.loop_ky:
    cmp r15d, 1
    jg .end_loop_ky

    mov eax, -1             ; Счетчик столбцов ядра (kx = -1)

; Цикл по столбцам ядра (kx = -1, 0, +1)
.loop_kx:
    cmp eax, 1
    jg .end_loop_kx

    ;----------------------------------------------------------
    ; Вычисляем координаты во временном буфере с проверкой границ
    ;----------------------------------------------------------
    
    ; Вычисляем pos_temp_y = clamp(y + 1 + ky, 0, temp_height-1)
    lea ecx, [r12 + 1]      ; y + 1 (temp buffer смещен на 1 пиксель)
    add ecx, r15d           ; y + 1 + ky
    cmp ecx, 0
    jge .y_ok1
    xor ecx, ecx            ; Если < 0, устанавливаем 0
.y_ok1:
    cmp ecx, r9d
    jl .y_ok2
    mov ecx, r9d            ; Если >= temp_height, устанавливаем temp_height-1
    dec ecx
.y_ok2:

    ; Вычисляем pos_temp_x = clamp(x + 1 + kx, 0, temp_width-1)
    lea edx, [r13 + 1]      ; x + 1
    add edx, eax            ; x + 1 + kx
    cmp edx, 0
    jge .x_ok1
    xor edx, edx            ; Если < 0, устанавливаем 0
.x_ok1:
    cmp edx, esi
    jl .x_ok2
    mov edx, esi            ; Если >= temp_width, устанавливаем temp_width-1
    dec edx
.x_ok2:

    ;----------------------------------------------------------
    ; Получаем значение пикселя из временного буфера
    ;----------------------------------------------------------
    ; Адрес = temp_buffer + (pos_temp_y * temp_width + pos_temp_x) * 3 + channel
    imul ecx, esi           ; pos_temp_y * temp_width
    add ecx, edx            ; + pos_temp_x
    imul ecx, 3             ; * 3 (3 канала на пиксель)
    add ecx, ebx            ; + текущий канал
    movzx edx, byte [r11 + rcx] ; Загружаем значение пикселя

    ;----------------------------------------------------------
    ; Получаем коэффициент ядра
    ;----------------------------------------------------------
    ; Адрес ядра = (ky + 1) * 3 + (kx + 1)
    mov ecx, r15d
    add ecx, 1              ; ky + 1 (0..2)
    imul ecx, 3             ; * 3 (переход к строке)
    add ecx, eax            ; + kx
    add ecx, 1              ; + 1 (kx + 1)
    movzx ecx, byte [kernel + rcx] ; Загружаем коэффициент ядра

    ;----------------------------------------------------------
    ; Суммируем произведение значения пикселя на коэффициент
    ;----------------------------------------------------------
    imul edx, ecx           ; Значение пикселя * коэффициент ядра
    add r14d, edx           ; Добавляем к сумме

    inc eax                 ; Следующий столбец ядра
    jmp .loop_kx

.end_loop_kx:
    inc r15d                ; Следующая строка ядра
    jmp .loop_ky

.end_loop_ky:
    ;----------------------------------------------------------
    ; Нормализация и запись результата
    ;----------------------------------------------------------
    ; sum = (sum + 8) >> 4 (деление на 16 с округлением)
    add r14d, 8             ; Добавляем 8 для округления
    shr r14d, 4             ; Деление на 16

    ; Вычисляем адрес в выходном буфере
    ; Адрес = output + (y * width + x) * 3 + channel
    mov ecx, r12d           ; y
    imul ecx, edi           ; * width
    add ecx, r13d           ; + x
    imul ecx, 3             ; * 3 (3 канала)
    add ecx, ebx            ; + текущий канал

    ; Записываем результат
    mov byte [r10 + rcx], r14b

    inc r13                 ; Следующий столбец
    jmp .loop_x

.end_loop_x:
    inc r12                 ; Следующая строка
    jmp .loop_y

.end_loop_y:
    inc ebx                 ; Следующий канал
    jmp .loop_channels

.end_loop_channels:
    ;----------------------------------------------------------
    ; Восстанавливаем регистры и возвращаем управление
    ;----------------------------------------------------------
    pop r10
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret