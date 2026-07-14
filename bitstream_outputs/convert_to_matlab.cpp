#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    const char *input_filename  = "output.txt";
    const char *output_filename = "bitstream_to_matlab.m";

    FILE *in = fopen(input_filename, "r");
    if (in == NULL) {
        printf("Error: could not open input file %s\n", input_filename);
        return 1;
    }

    FILE *out = fopen(output_filename, "w");
    if (out == NULL) {
        printf("Error: could not create output file %s\n", output_filename);
        fclose(in);
        return 1;
    }

    fprintf(out, "bitstream = [");

    int ch;
    int count = 0;

    while ((ch = fgetc(in)) != EOF) {
        if (ch == '0' || ch == '1') {
            fprintf(out, "%c ", ch);
            count++;

            /*
             * Optional: start a new line every 100 bits
             * so the MATLAB file is easier to read.
             */
            if (count % 100 == 0) {
                fprintf(out, "...\n");
            }
        }
    }

    fprintf(out, "];\n");

    fclose(in);
    fclose(out);

    printf("Created %s with %d bits.\n", output_filename, count);

    return 0;
}