CC = gcc
AS = nasm
CFLAGS = -Wall -Wextra -g
ASFLAGS = -f elf64
LDFLAGS = -no-pie -z noexecstack -lrt
SRCS_C = main.c
SRCS_ASM = src.s
EXE = bin

TARGET ?= asm  
OPT ?= O2      

CFLAGS += -$(OPT)


ifeq ($(TARGET),c)
    OBJS = $(SRCS_C:.c=.o)
    CFLAGS += -DUSE_C_VERSION
else
    OBJS = $(SRCS_C:.c=.o) $(SRCS_ASM:.s=.o)
endif

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