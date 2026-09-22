#include "FractalEngine.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

struct MDBCancel { atomic_bool cancelled; };
MDBCancel *mdb_cancel_create(void) {
    MDBCancel *flag = malloc(sizeof(MDBCancel));
    if (flag) atomic_init(&flag->cancelled, 0);
    return flag;
}
void mdb_cancel_set(MDBCancel *flag) { if (flag) atomic_store(&flag->cancelled, 1); }
int mdb_cancel_is_set(const MDBCancel *flag) { return flag && atomic_load(&flag->cancelled); }
void mdb_cancel_destroy(MDBCancel *flag) { free(flag); }

static double escape(double cr, double ci, int iterations, const MDBCancel *cancel) {
    // Analytic main-cardioid and period-two bulb tests avoid most interior work.
    double y2 = ci * ci, x = cr - 0.25, q = x * x + y2;
    if (q * (q + x) <= 0.25 * y2 || (cr + 1) * (cr + 1) + y2 <= 0.0625) return -1;
    double zr = 0, zi = 0, zr2 = 0, zi2 = 0;
    int n = 0;
    while (zr2 + zi2 <= 256.0 && n < iterations) {
        zi = 2 * zr * zi + ci;
        zr = zr2 - zi2 + cr;
        zr2 = zr * zr;
        zi2 = zi * zi;
        ++n;
        if ((n & 255) == 0 && mdb_cancel_is_set(cancel)) return -1;
    }
    if (n == iterations) return -1;
    return n + 1 - log2(log2(sqrt(zr2 + zi2)));
}

double mdb_escape(double cr, double ci, int iterations) { return escape(cr, ci, iterations, NULL); }

static void color(double value, double period, int palette, double *rgb) {
    if (value < 0) { rgb[0] = rgb[1] = rgb[2] = 0; return; }
    static const double colors[3][6][3] = {
        {{2, 20, 37}, {3, 30, 53}, {15, 44, 69}, {48, 82, 110}, {117, 158, 189}, {222, 239, 251}},
        {{0, 4, 14}, {3, 15, 47}, {9, 39, 93}, {22, 86, 162}, {84, 157, 227}, {222, 243, 255}},
        {{1, 10, 18}, {3, 24, 37}, {8, 49, 67}, {31, 96, 116}, {105, 175, 187}, {227, 249, 249}}
    };
    double t = pow(0.5 - 0.5 * cos(fmax(0, value) * 6.283185307179586 / period), 0.55);
    double position = t * 5;
    int a = (int)position;
    if (a > 4) a = 4;
    double mix = position - a;
    for (int c = 0; c < 3; c++) rgb[c] = colors[palette][a][c] * (1 - mix) + colors[palette][a + 1][c] * mix;
}

void mdb_render_rows(uint8_t *pixels, int width, int height, int first_row, int last_row,
                     double center_x, double center_y, double span, int iterations,
                     double color_period, int palette, int samples, const MDBCancel *cancel) {
    double pixel = span / width;
    for (int y = first_row; y < last_row; y++) {
        if (mdb_cancel_is_set(cancel)) return;
        for (int x = 0; x < width; x++) {
            if ((x & 63) == 0 && mdb_cancel_is_set(cancel)) return;
            double total[3] = {0, 0, 0};
            for (int sy = 0; sy < samples; sy++) for (int sx = 0; sx < samples; sx++) {
                double cr = center_x + (x + (sx + 0.5) / samples - width * 0.5) * pixel;
                double ci = center_y + (height * 0.5 - y - (sy + 0.5) / samples) * pixel;
                double rgb[3];
                color(escape(cr, ci, iterations, cancel), color_period, palette, rgb);
                for (int c = 0; c < 3; c++) total[c] += rgb[c];
            }
            size_t offset = ((size_t)y * width + x) * 4;
            for (int c = 0; c < 3; c++) pixels[offset + c] = (uint8_t)lround(total[c] / (samples * samples));
            pixels[offset + 3] = 255;
        }
    }
}
