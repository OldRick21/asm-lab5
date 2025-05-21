#!/bin/bash
# Тестирование C-версии
for opt in O0 O1 O2 O3 Ofast; do
    make clean >/dev/null 2>&1 && make TARGET=c OPT=$opt -j >/dev/null 2>&1
    echo -e "\e[33mTesting C $opt...\e[0m"
    ./bin input.jpeg output.jpeg
    echo ""
done

# Тестирование ASM-версии
make clean >/dev/null 2>&1 && make TARGET=asm OPT=o1 -j >/dev/null 2>&1
echo -e "\e[33mTesting ASM version...\e[0m"
./bin input.jpeg output.jpeg
echo ""
make clean >/dev/null 2>&1
