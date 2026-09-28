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

// Double-double arithmetic: each value is an unevaluated sum hi + lo, giving about 32 significant digits.
// Contraction is disabled so the error-free transformations below stay exact.
#pragma STDC FP_CONTRACT OFF
typedef struct { double hi, lo; } dd;
static inline dd two_sum(double a, double b) {
    double s = a + b, v = s - a;
    return (dd){s, (a - (s - v)) + (b - v)};
}
static inline dd quick_two_sum(double a, double b) { double s = a + b; return (dd){s, b - (s - a)}; }
static inline dd dd_add(dd a, dd b) {
    dd s = two_sum(a.hi, b.hi), t = two_sum(a.lo, b.lo);
    s = quick_two_sum(s.hi, s.lo + t.hi);
    return quick_two_sum(s.hi, s.lo + t.lo);
}
static inline dd dd_mul(dd a, dd b) {
    double p = a.hi * b.hi;
    return quick_two_sum(p, fma(a.hi, b.hi, -p) + (a.hi * b.lo + a.lo * b.hi));
}
static inline dd dd_sqr(dd a) {
    double p = a.hi * a.hi;
    return quick_two_sum(p, fma(a.hi, a.hi, -p) + 2 * a.hi * a.lo);
}

static double escape_dd(dd cr, dd ci, int iterations, const MDBCancel *cancel) {
    // Same bulb tests, with a margin: at deep zoom a view can sit right on the cardioid's edge,
    // where a double-precision test would misclassify exterior points.
    double y2 = ci.hi * ci.hi, x = cr.hi - 0.25, q = x * x + y2;
    if (q * (q + x) < 0.25 * y2 - 1e-9 || (cr.hi + 1) * (cr.hi + 1) + y2 < 0.0625 - 1e-9) return -1;
    dd zr = {0, 0}, zi = {0, 0}, zr2 = {0, 0}, zi2 = {0, 0};
    int n = 0;
    while (zr2.hi + zi2.hi <= 256.0 && n < iterations) {
        dd product = dd_mul(zr, zi);
        zi = dd_add((dd){2 * product.hi, 2 * product.lo}, ci);
        zr = dd_add(dd_add(zr2, (dd){-zi2.hi, -zi2.lo}), cr);
        zr2 = dd_sqr(zr);
        zi2 = dd_sqr(zi);
        ++n;
        if ((n & 255) == 0 && mdb_cancel_is_set(cancel)) return -1;
    }
    if (n == iterations) return -1;
    return n + 1 - log2(log2(sqrt(zr2.hi + zi2.hi)));
}
#pragma STDC FP_CONTRACT ON

double mdb_escape_dd(double cr, double cr_lo, double ci, double ci_lo, int iterations) {
    return escape_dd((dd){cr, cr_lo}, (dd){ci, ci_lo}, iterations, NULL);
}

static void color(double value, double period, int palette, double *rgb) {
    if (value < 0) { rgb[0] = rgb[1] = rgb[2] = 0; return; }
    static const double colors[8][6][3] = {
        {{2, 20, 37}, {3, 30, 53}, {15, 44, 69}, {48, 82, 110}, {117, 158, 189}, {222, 239, 251}},
        {{0, 4, 14}, {3, 15, 47}, {9, 39, 93}, {22, 86, 162}, {84, 157, 227}, {222, 243, 255}},
        {{1, 10, 18}, {3, 24, 37}, {8, 49, 67}, {31, 96, 116}, {105, 175, 187}, {227, 249, 249}},
        /* Ember: smoldering black through crimson and orange to white-hot gold */
        {{10, 2, 4}, {52, 6, 12}, {128, 20, 18}, {210, 72, 20}, {250, 164, 52}, {255, 243, 205}},
        /* Aurora: polar night through teal and green to pale mint */
        {{3, 6, 24}, {28, 20, 78}, {18, 88, 118}, {36, 186, 148}, {150, 238, 168}, {236, 255, 236}},
        /* Sunset: violet dusk through magenta and coral to warm peach */
        {{12, 4, 30}, {62, 12, 82}, {150, 30, 102}, {228, 82, 82}, {255, 160, 84}, {255, 232, 176}},
        /* Nebula: deep space through violet and orchid to starlight pink */
        {{6, 2, 16}, {36, 8, 62}, {92, 22, 134}, {168, 62, 204}, {228, 142, 236}, {255, 232, 255}},
        /* Graphite: neutral monochrome, like a pencil drawing or silver print */
        {{4, 4, 6}, {22, 22, 26}, {55, 55, 62}, {110, 110, 120}, {182, 182, 190}, {246, 246, 248}}
    };
    double t = pow(0.5 - 0.5 * cos(fmax(0, value) * 6.283185307179586 / period), 0.55);
    double position = t * 5;
    int a = (int)position;
    if (a > 4) a = 4;
    double mix = position - a;
    for (int c = 0; c < 3; c++) rgb[c] = colors[palette][a][c] * (1 - mix) + colors[palette][a + 1][c] * mix;
}

void mdb_render_rows(uint8_t *pixels, int width, int height, int first_row, int last_row,
                     double center_x, double center_x_lo, double center_y, double center_y_lo,
                     double span, int iterations, double color_period, int palette, int samples,
                     const MDBCancel *cancel) {
    double pixel = span / width;
    // Doubles resolve about 1e-16 near the set, so switch to double-double well before pixels get that small.
    int precise = span < MDB_DOUBLE_DOUBLE_SPAN;
    dd center_r = {center_x, center_x_lo}, center_i = {center_y, center_y_lo};
    for (int y = first_row; y < last_row; y++) {
        if (mdb_cancel_is_set(cancel)) return;
        for (int x = 0; x < width; x++) {
            if ((x & 63) == 0 && mdb_cancel_is_set(cancel)) return;
            double total[3] = {0, 0, 0};
            for (int sy = 0; sy < samples; sy++) for (int sx = 0; sx < samples; sx++) {
                double dx = (x + (sx + 0.5) / samples - width * 0.5) * pixel;
                double dy = (height * 0.5 - y - (sy + 0.5) / samples) * pixel;
                double value = precise
                    ? escape_dd(dd_add(center_r, (dd){dx, 0}), dd_add(center_i, (dd){dy, 0}), iterations, cancel)
                    : escape(center_x + dx, center_y + dy, iterations, cancel);
                double rgb[3];
                color(value, color_period, palette, rgb);
                for (int c = 0; c < 3; c++) total[c] += rgb[c];
            }
            size_t offset = ((size_t)y * width + x) * 4;
            for (int c = 0; c < 3; c++) pixels[offset + c] = (uint8_t)lround(total[c] / (samples * samples));
            pixels[offset + 3] = 255;
        }
    }
}
