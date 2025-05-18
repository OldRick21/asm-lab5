# Добавляем -no-pie в LDFLAGS
LDFLAGS = -no-pie -z noexecstack

# Остальная часть Makefile остается без изменений
CC = gcc
AS = nasm
CFLAGS = -O3 -Wall -Wextra
ASFLAGS = -f elf64
SRCS_C = main.c
SRCS_ASM = src.s
OBJS = $(SRCS_C:.c=.o) $(SRCS_ASM:.s=.o)
EXE = bin

all: $(EXE)

clean:
	rm -rf $(EXE) $(OBJS)

$(EXE): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -ljpeg -lm -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

.PHONY: all clean