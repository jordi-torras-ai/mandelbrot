#ifndef FRACTAL_ENGINE_H
#define FRACTAL_ENGINE_H
#include <stdint.h>

typedef struct MDBCancel MDBCancel;
MDBCancel *mdb_cancel_create(void);
void mdb_cancel_set(MDBCancel *flag);
int mdb_cancel_is_set(const MDBCancel *flag);
void mdb_cancel_destroy(MDBCancel *flag);

// Returns -1 for points that do not escape within the iteration budget.
double mdb_escape(double cr, double ci, int iterations);
// RGBA8, top-to-bottom; each worker owns a disjoint range of rows.
void mdb_render_rows(uint8_t *pixels, int width, int height,
                     int first_row, int last_row, double center_x,
                     double center_y, double span, int iterations,
                     double color_period, int palette, int samples,
                     const MDBCancel *cancel);
#endif
