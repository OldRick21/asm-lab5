// Основной заголовочные файлы
#include <stdio.h>
#include <stdlib.h>
#include <jpeglib.h>    // Для работы с JPEG
#include <string.h>
#include <stdint.h>     // Для точных целочисленных типов
#include <time.h>       // Для измерения времени выполнения

// Объявление ассемблерной функции
extern void gaussian_blur_asm(uint8_t *temp, uint8_t *output, int temp_width, int temp_height, int width, int height);

// C-реализация размытия по Гауссу
void gaussian_blur_c(uint8_t *temp, uint8_t *output, int temp_width, int temp_height, int width, int height) {
    // Ядро Гаусса 3x3 (сумма коэффициентов = 16)
    const int kernel[3][3] = {
        {1, 2, 1},
        {2, 4, 2},
        {1, 2, 1}
    };

    // Проход по всем цветовым каналам (R, G, B)
    for (int c = 0; c < 3; c++) {
        // Проход по всем пикселям выходного изображения
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int sum = 0;
                
                // Свертка с ядром Гаусса 3x3
                for (int ky = -1; ky <= 1; ky++) {
                    for (int kx = -1; kx <= 1; kx++) {
                        // Расчет позиции во временном буфере с проверкой границ
                        int pos_temp_y = y + 1 + ky;
                        int pos_temp_x = x + 1 + kx;
                        pos_temp_y = (pos_temp_y < 0) ? 0 : (pos_temp_y >= temp_height) ? temp_height - 1 : pos_temp_y;
                        pos_temp_x = (pos_temp_x < 0) ? 0 : (pos_temp_x >= temp_width) ? temp_width - 1 : pos_temp_x;
                        
                        // Получение пикселя и умножение на коэффициент ядра
                        uint8_t pixel = temp[(pos_temp_y * temp_width + pos_temp_x) * 3 + c];
                        sum += pixel * kernel[ky + 1][kx + 1];
                    }
                }
                
                // Нормализация и запись результата
                sum = (sum + 8) >> 4; // Эквивалентно делению на 16 с округлением
                output[(y * width + x) * 3 + c] = (uint8_t)sum;
            }
        }
    }
}

// Функция чтения JPEG файла
void read_jpeg(const char *filename, uint8_t **buffer, int *width, int *height) {
    // Инициализация структур libjpeg
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    FILE *infile;

    // Открытие файла и проверка ошибок
    if ((infile = fopen(filename, "rb")) == NULL) {
        fprintf(stderr, "Error opening file %s\n", filename);
        exit(1);
    }

    //  // Проверка сигнатуры JPEG (0xFFD8)
    // if (fread(header, 1, 2, infile) != 2 || 
    //     header[0] != 0xFF || 
    //     header[1] != 0xD8) {
    //     fclose(infile);
    //     fprintf(stderr, "File %s is not a JPEG\n", filename);
    //     exit(1);
    // }
    // fseek(infile, 0, SEEK_SET); // Возврат к началу файла

    // Настройка декомпрессора
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, infile);
    jpeg_read_header(&cinfo, TRUE);
    jpeg_start_decompress(&cinfo);

    // Выделение памяти под изображение
    *width = cinfo.output_width;
    *height = cinfo.output_height;
    *buffer = malloc(*width * *height * 3); // 3 канала (RGB)

    // Построчное чтение данных
    JSAMPROW row_pointer[1];
    while (cinfo.output_scanline < cinfo.output_height) {
        row_pointer[0] = *buffer + cinfo.output_scanline * *width * 3;
        jpeg_read_scanlines(&cinfo, row_pointer, 1);
    }

    // Завершение декомпрессии и очистка
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(infile);
}

// Функция записи JPEG файла
void write_jpeg(const char *filename, uint8_t *buffer, int width, int height) {
    // Аналогично read_jpeg, но для записи
    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    FILE *outfile;

    if ((outfile = fopen(filename, "wb")) == NULL) {
        fprintf(stderr, "Error opening file %s\n", filename);
        exit(1);
    }

    // Настройка компрессора
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, outfile);

    cinfo.image_width = width;
    cinfo.image_height = height;
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, 90, TRUE); // Качество 90%
    jpeg_start_compress(&cinfo, TRUE);

    // Построчная запись
    JSAMPROW row_pointer[1];
    while (cinfo.next_scanline < cinfo.image_height) {
        row_pointer[0] = buffer + cinfo.next_scanline * width * 3;
        jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }

    // Финализация и очистка
    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);
    fclose(outfile);
}

int main(int argc, char **argv) {
    // Проверка аргументов командной строки
    if (argc != 3) {
        printf("Usage: %s <input.jpg> <output.jpg>\n", argv[0]);
        return 1;
    }

    // Чтение исходного изображения
    uint8_t *original = NULL;
    int width, height;
    read_jpeg(argv[1], &original, &width, &height);

    // Создание временного буфера с расширенными границами
    int temp_width = width + 2;
    int temp_height = height + 2;
    uint8_t *temp = malloc(temp_width * temp_height * 3);

    // Заполнение временного буфера (добавление границ)
    for (int c = 0; c < 3; c++) {
        for (int y = 0; y < temp_height; y++) {
            for (int x = 0; x < temp_width; x++) {
                // Копирование с обработкой граничных условий
                int src_x = x - 1;
                int src_y = y - 1;
                src_x = (src_x < 0) ? 0 : (src_x >= width) ? width - 1 : src_x;
                src_y = (src_y < 0) ? 0 : (src_y >= height) ? height - 1 : src_y;
                temp[(y * temp_width + x) * 3 + c] = original[(src_y * width + src_x) * 3 + c];
            }
        }
    }

    // Выделение памяти под результат
    uint8_t *output = malloc(width * height * 3);

    // Замер времени выполнения
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    // Выбор реализации (C или ASM через флаг компиляции)
    #ifdef USE_C_VERSION
        gaussian_blur_c(temp, output, temp_width, temp_height, width, height);
    #else
        gaussian_blur_asm(temp, output, temp_width, temp_height, width, height);
    #endif
    
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    printf("\033[33mBlur time:\033[0m \033[36m%f\033[0m \033[33mseconds\033[0m\n", elapsed);

    // Сохранение результата
    write_jpeg(argv[2], output, width, height);

    // Освобождение памяти
    free(original);
    free(temp);
    free(output);

    return 0;
}