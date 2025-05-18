#include <stdio.h>
#include <stdlib.h>
#include <jpeglib.h>
#include <string.h>
#include <stdint.h>

extern void gaussian_blur_asm(uint8_t *temp, uint8_t *output, int temp_width, int temp_height, int width, int height);

void read_jpeg(const char *filename, uint8_t **buffer, int *width, int *height) {
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    FILE *infile;

    if ((infile = fopen(filename, "rb")) == NULL) {
        fprintf(stderr, "Error opening file %s\n", filename);
        exit(1);
    }

    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, infile);
    jpeg_read_header(&cinfo, TRUE);
    jpeg_start_decompress(&cinfo);

    *width = cinfo.output_width;
    *height = cinfo.output_height;
    int channels = cinfo.output_components;
    *buffer = (uint8_t*)malloc(*width * *height * channels);

    JSAMPROW row_pointer[1];
    while (cinfo.output_scanline < cinfo.output_height) {
        row_pointer[0] = *buffer + cinfo.output_scanline * *width * channels;
        jpeg_read_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(infile);
}

void write_jpeg(const char *filename, uint8_t *buffer, int width, int height) {
    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    FILE *outfile;

    if ((outfile = fopen(filename, "wb")) == NULL) {
        fprintf(stderr, "Error opening file %s\n", filename);
        exit(1);
    }

    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, outfile);

    cinfo.image_width = width;
    cinfo.image_height = height;
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, 90, TRUE);
    jpeg_start_compress(&cinfo, TRUE);

    JSAMPROW row_pointer[1];
    while (cinfo.next_scanline < cinfo.image_height) {
        row_pointer[0] = buffer + cinfo.next_scanline * width * 3;
        jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);
    fclose(outfile);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <input.jpg> <output.jpg>\n", argv[0]);
        return 1;
    }

    uint8_t *original = NULL;
    int width, height;
    read_jpeg(argv[1], &original, &width, &height);

    int temp_width = width + 2;
    int temp_height = height + 2;
    uint8_t *temp = (uint8_t*)malloc(temp_width * temp_height * 3);

    for (int c = 0; c < 3; c++) {
        for (int y = 0; y < temp_height; y++) {
            for (int x = 0; x < temp_width; x++) {
                int src_x = x - 1;
                int src_y = y - 1;
                src_x = (src_x < 0) ? 0 : (src_x >= width) ? width - 1 : src_x;
                src_y = (src_y < 0) ? 0 : (src_y >= height) ? height - 1 : src_y;
                temp[(y * temp_width + x) * 3 + c] = original[(src_y * width + src_x) * 3 + c];
            }
        }
    }

    uint8_t *output = (uint8_t*)malloc(width * height * 3);
    gaussian_blur_asm(temp, output, temp_width, temp_height, width, height);

    write_jpeg(argv[2], output, width, height);

    free(original);
    free(temp);
    free(output);

    return 0;
}