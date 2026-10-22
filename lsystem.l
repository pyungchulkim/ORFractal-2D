/* Ordered Random Fractal 2D (ORFractal-2D) - see description.txt for details.
 * by Pyungchul Kim, 2026
 * https://orderedrandom.com
 */

#include <lpfgall.h>
#include <GL/gl.h>

////////////////////////////////////////////////////////////////////////
// Control parameters to run the simulation and render the results
////////////////////////////////////////////////////////////////////////

const int SEED = 85769;			// seed for random generator. 0 for no seed setting
const float RANDOMNESS = 0.2;		// randomness control. 0.01 for almost no random, 0.5 for almost random
const int MAX_NODES = 4000;		// # of nodes to stop simulation
const int MAX_ITERATIONS= 5;		// # of iteration stop simulation
const int MAX_CONTOURS = LAST_CONTOUR - 1; // The last contour is named as "LAST_CONTOUR"
const int CONTOUR_SIDES = 128;		// # of sides in a node contour
const bool PAINT_LINE = true;		// draw contour line for shapes
const bool PAINT_SOLID = true;		// fill color as solid for shapes
const bool PAINT_TRANSPARENT = true;	// transparent (true) or opaque (false) for colors
const int LINE_WIDTH = 10;		// line width
const int LINE_COLOR = 255;		// line color. -1 for the same color as shape.
const int MAX_COLORS = 256;		// color range = [0, MAX_COLORS)
const bool USE_CUSTOM_PALETTE = true;	// use custome palette rather than L-studio colors
const bool DRAW_BOX = true;		// draw the reference box
const float BOX_WIDTH = 4000.0;		// reference box width
const float BOX_HEIGHT = 3000.0;	// reference box height
const bool KEEP_HEAD_ANGLE = true;	// if true, the head angle stays the same during growth

////////////////////////////////////////////////
// Macros
////////////////////////////////////////////////

#define DIM(ary)	(sizeof(ary) / sizeof(ary[0]))	// dimension of an array
#define ROUND(f)	((int)(f + 0.5f))		// simple round for positive float
#define MIN(a, b) 	(((a) < (b)) ? (a) : (b))	// pick min
#define MAX(a, b) 	(((a) > (b)) ? (a) : (b))	// pick max

/////////////////////////////////////////////////////////////
// Forward declarations of types, functions and modules
/////////////////////////////////////////////////////////////

/* Gene for a node - dictates how it grows */
typedef struct {		
	int idContour;		// ID for the base contour
	int maxFanouts;		// max fanouts when no prunning happens.
	float prunRate;		// pruning rate. 0 for no-pruning
	float maxAngle;		// branches are distributed within [-p3, p3] degree from the top.
	float maxRotation;	// branches rotate randomly within [-p4, p4] degree.
	float scaleRate;	// rate of the size (scale) of the new node
	float gapRate;		// rate of distance between the contours of the mother and new node.
				// 0 for right next, 1 for one node apart, -0.5 for half overlapped, and so on.
	int color;		// color. -1 for a random pick
} Gene;

/* Seeding batch */
typedef struct {
	int idGene;			// genes id 
	int nSeeds;			// # of seeds to plant 
	float minScale, maxScale;	// initial scale range
} Batch;

typedef void* NodeHandle;	// generic pointer to a node

/* Node2D - generic structure for all nodes using 2D contour as shape */
typedef struct Node2D {
	int id;			// unique id of the node
	int birth;		// iteration at which the node was created
	NodeHandle pMother;	// the mother node
	int idGene;		// genes id
	V2f start;		// "directional relative" move to start location
	V2f direction;		// direction: x=angle, y=rotation
	float scale;		// scaling
	int color;		// color
} Node2D;

/* Contour data structure - it holds all vertices and edges as well as
 * the map to locate a vertex at a degree of [0, 360). Note that
 * (1) the degree grows counter-clock wise from the top;
 * (2) the edge vector is relative to its previous edge, assuming it started
 *     at edges[0] with degree 0 (straight-up direction) 
 */
typedef struct {
	V2f vertices[CONTOUR_SIDES];	// coordinates
	V2f edges[CONTOUR_SIDES];	// edges: x=angle, y=distance
	int angleToVertices[360];	// map from angle (int) to vertex id
} Contour;

/* production rules for LPFG */
module Seeding();
module GrowNode(NodeHandle);

module Initialize();
module DrawNode(NodeHandle);
module DrawBox(float, float);

/* Other functions */
void generateSeedsCoordinates(float, float, int, V2f*); // generate seeds coordinates
float gRandom(float);			// Gaussian dist random generator
float uRandom(float, float);		// Uniform dist random within [min, max)
V2f getContourCoord(int, float); 	// get coordinate from a contour
V2f rotateVector(V2f&, float); 		// rotate a vector

/////////////////////////////////////////////////////////////
// Global variables
/////////////////////////////////////////////////////////////

/* Genes and batches of seeds are being used in the simulation */
Gene genes[] = {
  // idContour, maxFanouts, prunRate, maxAngle, maxRotation, scaleRate, gapRate, color
  {  0,         3,          0.8,      170,      0,           0.8,       0.2,     -1},
  {  1,         2,          0.7,      90,       0,           0.9,       2.5,     -1},
  {  2,         2,          0.8,      170,      0,           0.7,       2.5,     -1},
  {  3,         3,          0.75,     170,     45,           0.8,       0.0,     -1},
  {  4,         2,          0.8,      90,      30,           0.7,       -0.5,    -1},
  {  5,         2,          0.9,      170,      0,           0.7,       2.5,     -1},
  {  6,         2,          0.8,      90,      30,           0.7,       -0.5,    -1},
  {  7,         2,          0.5,      90,       0,           0.9,       2.5,     -1},
};

Batch batches[] {
	{0, 10, 300, 500},
	{1, 5, 1000, 1200},
	{2, 10, 200, 400},
	{3, 3, 800, 2000},
	{4, 4, 1000, 5000},
	{5, 10, 400, 1000},
	{6, 3, 1000, 5000},
	{7, 5, 1000, 1300},
};

/* Custom palette for colors picked from L-Studio colors */
int palette[] {
     // 0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240
	0, 48+3, 80, 128, 160, 160+3, 208 
};

int currRandomSeed;		// current seed for random generators
int currIteration;		// current iteration number of the simulation
int nodesCreated;		// # of nodes created so far
int nodesCreatedLast;		// # of nodes created until the last iteration
Contour contours[MAX_CONTOURS];	// contour coordinates cache

/* OpenGL functions entry */
extern "C" { __attribute__((__stdcall__)) void* wglGetProcAddress(const char*); }
typedef void (__attribute__((__stdcall__)) *PFNGLBLENDEQUATIONPROC)(unsigned int mode);

PFNGLBLENDEQUATIONPROC glBlendEquation = NULL;

/////////////////////////////////////////////////////////////
// LPFG Simulation codes
/////////////////////////////////////////////////////////////
Start: 
{
  currIteration = 0;	// current iteration no.
  nodesCreated = 0;	// # of nodes created (not drawn)
  if (SEED != 0)
    currRandomSeed = SEED;
  else
    currRandomSeed = (int)ran(100000);
  sran(currRandomSeed);	// set random seed

  // Output the current random seed in case I want to regenerate the exact drawing
  Printf("Start simulation with random seed: %d.\n", currRandomSeed);
}

StartEach: 
{
  nodesCreatedLast = nodesCreated;
  Printf("Iteration: %d starts with %d nodes.\n", currIteration, nodesCreated);
}

EndEach: 
{
  // Stop simulation when either iterations have exhausted or 
  // no new nodes were created during the current iteration.
  if (currIteration >= MAX_ITERATIONS || nodesCreated == nodesCreatedLast) {
    Printf("\nSimulation ended. In total, %d nodes have been created.\n", nodesCreated);
    Stop();
  }

  currIteration++;
}

derivation length: 100000;

Axiom: 	Initialize() // Initialize data structures before production
	DrawBox(BOX_WIDTH, BOX_HEIGHT) // reference box
	SetWidth(LINE_WIDTH)
	Seeding();

/* Seed initial nodes for the genes.
 */
Seeding() : 
{
  int nTotalSeeds = 0;
  for (int i = 0; i < DIM(batches); i++)
    nTotalSeeds += batches[i].nSeeds;

  // Flatten to randomize
  Batch *flatBatches = new Batch[nTotalSeeds];
  for (int i = 0, c = 0; i < DIM(batches); i++)
    for (int j = 0; j < batches[i].nSeeds; j++)
      flatBatches[c++] = batches[i];

  // Randomize
  for (int i = nTotalSeeds - 1; i > 0; i--)
    std::swap(flatBatches[i], flatBatches[(int)ran(i + 1)]);

  // Generate seeds coordinates
  V2f *coords = new V2f[nTotalSeeds];
  generateSeedsCoordinates(BOX_WIDTH, BOX_HEIGHT, nTotalSeeds, coords);

  for (int i = 0; i < nTotalSeeds; i++) {

    Batch *pBatch = &flatBatches[i];
    if (pBatch->idGene < 0 || pBatch->idGene >= DIM(genes)) {
      Printf("Invalid idGene: %d.\n", pBatch->idGene);
      Stop();
    }

    // Detemine the location and initial scale
    V2f start = coords[i];
    float scale = uRandom(pBatch->minScale, pBatch->maxScale);

    // Allocate a node and populate the node specific info
    NodeHandle pNode = NULL;
    Gene *pGene = &genes[pBatch->idGene];

    Node2D* pn = new Node2D;
    pn->id = nodesCreated++;
    pn->birth = currIteration;
    pn->pMother = NULL;
    pn->idGene = pBatch->idGene;
    pn->start = start;

    // set the direction the node
    if (KEEP_HEAD_ANGLE) {  // no change in head angle - straight up
      pn->direction.x = 0;
    }
    else {	// set it as if it grew out of its mother with the gene settings
      pn->direction.x = gRandom(pGene->maxAngle) - pGene->maxAngle;
    }
    pn->direction.y = uRandom(-pGene->maxRotation, pGene->maxRotation);

    pn->scale = scale;
    pn->color = pGene->color;
    if (pn->color < 0)	{ // unspecified. random pick
      if (USE_CUSTOM_PALETTE)
	pn->color = palette[(int)ran(DIM(palette))] + 1;
      else
	pn->color = (int)ran(MAX_COLORS);
    }
    pNode = pn;

    nproduce SB();
    nproduce GrowNode(pNode);
    nproduce EB();
  }

  Printf("Seeding() completed with %d seeds.\n", nTotalSeeds); 

  delete[] flatBatches;
  delete[] coords;
  produce ;
}

/* Draw the current node and grow next nodes from it.
 */
GrowNode(pNode) :
{
  // Draw the node
  nproduce DrawNode(pNode);

  if (nodesCreated >= MAX_NODES) {	// maxed out. no more growth
    produce ;
    return;
  }

  Node2D *pThis = (Node2D *)pNode;
  Gene *pGene = &genes[pThis->idGene];

  // Generate angles for fanouts distributed within [-maxAngle, maxAngle]
  int maxFanouts = pGene->maxFanouts;
  int maxAngle = pGene->maxAngle;
  float *fanouts = new float[maxFanouts];
  float curr = (maxFanouts <= 1) ? 0 : -maxAngle;
  float delta = (maxFanouts <= 1) ? 360 : (2 * maxAngle) / (maxFanouts - 1);
  for (int i = 0; i < maxFanouts; i++, curr += delta) {
    fanouts[i] = curr + gRandom(delta) - delta;
  }

  // Generate new node at the fanouts
  for (int i = 0; i < maxFanouts; i++) {
    if (ran(1.0) < pGene->prunRate)
      continue;	// prun (skip) it

    Node2D *pn = new Node2D;
    pn->id = nodesCreated++;
    pn->birth = currIteration;
    pn->pMother = pThis;
    pn->idGene = pThis->idGene;

    // set the direction and rotation of the node
    if (KEEP_HEAD_ANGLE) {  // no change in head angle
      pn->direction.x = 0;
    }
    else {
      pn->direction.x = fanouts[i];	// head along the fanout angle
    }
    pn->direction.y = uRandom(-pGene->maxRotation, pGene->maxRotation);

    pn->scale = pThis->scale * gRandom(pGene->scaleRate);
    pn->color = pThis->color;

    // Calculate the center coordinate of the new node.
    // The gap is distance between v1 and v2 where v1 is a vertex of
    // mother node and v2 is a vertex of the new node, and the line
    // connecting v1, v2 are the same line connecting the centers of the
    // two nodes. The gap in general indicates the gap between
    // the mother node and the new node contours.

    V2f v1 = getContourCoord(pGene->idContour, fanouts[i]) * pThis->scale;
    float gapRate = gRandom(pGene->gapRate);
    V2f v2 = v1 * (1 + gapRate);	// move by gap rate
    float d2 = 180 + fanouts[i] - pn->direction.x;
    V2f v3 = getContourCoord(pGene->idContour, d2) * pn->scale;
    pn->start = v2 - rotateVector(v3, pn->direction.x); // the center of the new node

    nproduce SB();
    nproduce GrowNode(pn);
    nproduce EB();
  }

  delete[] fanouts;  
  produce ;	// done with the node
}

/* TRICK: I need to populate the contour coordinates before any productions
 * so my node growth algorithm can use the coordinates.
 * However, those coordinates are available only at interpretation stage.
 * Having a query such as GetPos() at predecessor of a rule triggers
 * interpretation stage prior to production.
 */
GetPos(x, y, z) : { }

/* Rules to interpret the production to draw */

interpretation:

/* Initialize the interpretation phase in terms of setting the environment
 * and preparing data structure to be re-used for other interpretation modules
 */
Initialize() : 
{
  // Use low-level OpenGL directly to set up blending mode
  // to simulate pigment mixing when in the transparent mode.
  if (PAINT_TRANSPARENT) {
    if (!glBlendEquation) {	// load glBlendEquation()
      glBlendEquation = (PFNGLBLENDEQUATIONPROC)wglGetProcAddress("glBlendEquation");
    }
    if (glBlendEquation) {	// simulate pigment mixing
      glEnable(GL_BLEND);
      glBlendEquation(0x8006 /*=GL_FUNC_ADD*/);
      glBlendFunc(GL_DST_COLOR, GL_ZERO);
    }
  }

  nproduce SB();

  // Load the node contour vectors
  for (int i = 0; i < MAX_CONTOURS; i++) {

    int nSides = DIM(contours[i].vertices);
    int cid = i + 1;	// contour id in LPFG starts from 1 
    nproduce CurrentContour(cid);
    nproduce ContourSides(255);	// set the sides highest to read in

    // Load and cache the contour vertices
    for (int s = 0; s < nSides; s++) {
      float t = (float)s / nSides;
      V2f v = curveXY(cid, t);
      contours[i].vertices[s] = curveXY(cid, t);
    }

    // Populate node edges from the vertices so we can use turtle
    // (Left(a) f(l)) to draw the contour.
    // Note that f(l) is relative to the current direction/position.
    // Also note that the edges needs to be plotted sequentially from
    // 0-th edge with straight up turtle (90-degree in hypot() world).
    float pa = 90;		// previous angle relative to hypot()
    for (int s = 0; s < nSides; s++) {
      int ns = (s == nSides - 1) ? 0 : (s + 1); // next vertex index
      V2f d = contours[i].vertices[ns] - contours[i].vertices[s];
      float a = atan2(d.y, d.x) * (180.0 / M_PI);	// angle
      contours[i].edges[s].x = a - pa;	// relative to previous angle
      contours[i].edges[s].y = hypot(d.y, d.x);	// distance
      pa = a;
    }

    // Populate angletoVertices for direct look up a vertice by angle later 
    // Note that the angle grows counterclockwise from the top
    float *angles = new float[nSides];
    for (int s = 0; s < nSides; s++) {
      V2f v = contours[i].vertices[s];
      angles[s] = atan2(v.y, v.x) * (180.0 / M_PI); // angle in [-180, 180)
      angles[s] -= 90;	// adjust it so the top is angle 0.
    }
    for (int a = 0; a < DIM(contours[i].angleToVertices); a++) {
      // locate the vertex closest to angle a
      float min = 1e9;
      int mv = -1;
      for (int s = 0; s < nSides; s++) {
	float d = abs(fmod(angles[s] + 360.0, 360.0) - a);
	if (d < min) {
	  min = d;
	  mv = s;
	}
      }
      contours[i].angleToVertices[a] = mv;
    }
    delete[] angles;
  } 

  produce EB();
}

/* Draw the node with the direction and shape information. */
DrawNode(pNode) : 
{
  Node2D *pThis = (Node2D *)pNode;
  int ci = genes[pThis->idGene].idContour;

  // Make a directional relative move to the new center position.
  nproduce Right(90) g(pThis->start.x)
	   Left(90) g(pThis->start.y);

  // Set the direction and color
  nproduce Left(pThis->direction.x) RollR(pThis->direction.y);

  // Start the shape. Make sure the polygon to be enclosed in a block
  // so the turtle center location and direction remain unchanged.
  nproduce SB();

  // Move to the first (starting) vertex location.
  V2f start = contours[ci].vertices[0] * pThis->scale;
  nproduce Right(90) g(start.x) Left(90) g(start.y);

  // Draw the shape
  if (PAINT_LINE) {	// draw the contour line
    nproduce SB();
    nproduce SetColor(LINE_COLOR == 0 ? pThis->color : LINE_COLOR);
    int nSides = DIM(contours[ci].edges);
    for (int i = 0; i < nSides; i++) {
      float l = contours[ci].edges[i].y * pThis->scale;
      nproduce Left(contours[ci].edges[i].x) F(l);
    }
    nproduce EB();
  }
  if (PAINT_SOLID) {	// fill color inside the shape
    nproduce SB();
    nproduce SetColor(pThis->color);
    nproduce SP();
    int nSides = DIM(contours[ci].edges);
    for (int i = 0; i < nSides; i++) {
      float l = contours[ci].edges[i].y * pThis->scale;
      nproduce Left(contours[ci].edges[i].x) f(l);
    }
    nproduce EP();
    nproduce EB();
  }

  produce EB();
}

/* circular rod (cylinder) *
L(l) --> [&(90)@c] F(l) [&(90)@c]
*/

/* Draw the reference box */
DrawBox(w,h) : 
{
  if (DRAW_BOX) {
    nproduce SB()SetWidth(10)SetColor(15)
		 MoveTo(w/2,0,0)F(h)Left(90)F(w)Left(90)F(h)Left(90)F(w)
	     EB();
  }
  produce ;
}

////////////////////////////////////////////////
// My Own Functions
////////////////////////////////////////////////

/* Calculates the coordinates of the seeds using Core Poisson Disk Sampling function.
 * Generates EXACTLY nSeeds using an adaptive Poisson Disk relaxation strategy.
 * Populates the pre-allocated points array completely.
 */
void generateSeedsCoordinates(float width, float height, int nSeeds, V2f* coords)
{
  if (nSeeds <= 0 || coords == NULL)
    return;

  // 1. Initial optimal radius calculation
  float r = sqrt((0.65 * width * height) / nSeeds);
  int attempts = 30;

  // Setup spatial grid based on the original starting radius
  float cellSize = r / sqrt(2.0);
  int cols = (int)ceil(width / cellSize);
  int rows = (int)ceil(height / cellSize);
  int cells = cols * rows;

  int* grid = new int[cells];
  for (int i = 0; i < cells; i++) grid[i] = -1;

  int* activeList = new int[nSeeds];
  
  int seedsCount = 0;
  int activeCount = 0;

  // Place the first seed point
  V2f p0 = { uRandom(0, width), uRandom(0, height) };
  coords[seedsCount] = p0;
  activeList[activeCount] = seedsCount;
  
  int c0 = (int)(p0.x / cellSize);
  int r0 = (int)(p0.y / cellSize);
  if (c0 >= 0 && c0 < cols && r0 >= 0 && r0 < rows) {
    grid[c0 + r0 * cols] = seedsCount;
  }
  
  seedsCount++;
  activeCount++;

  // 2. Main Generation Loop
  while (seedsCount < nSeeds) {
    
    // --- RELAXATION FALLBACK ---
    if (activeCount == 0) {
      r *= 0.85; // Decrease radius by 15%
      
      // Re-populate active list with ALL points generated so far
      for (int p = 0; p < seedsCount; p++) {
        activeList[p] = p;
      }
      activeCount = seedsCount;
    }

    int activeIdx = (int)ran(activeCount);
    int seedIdx = activeList[activeIdx];
    V2f activePoint = coords[seedIdx];
    bool found = false;

    for (int i = 0; i < attempts; i++) {
      float angle = uRandom(0, 2.0 * M_PI);
      float dist = uRandom(r, 2.0 * r);
      
      V2f candidate;
      candidate.x = activePoint.x + dist * cos(angle);
      candidate.y = activePoint.y + dist * sin(angle);
      if (candidate.x >= 0 && candidate.x < width && candidate.y >= 0 && candidate.y < height) {
        int col = (int)(candidate.x / cellSize);
        int row = (int)(candidate.y / cellSize);

        bool tooClose = false;
        int startCol = (col - 2 < 0) ? 0 : col - 2;
        int endCol = (col + 2 >= cols) ? cols - 1 : col + 2;
        int startRow = (row - 2 < 0) ? 0 : row - 2;
        int endRow = (row + 2 >= rows) ? rows - 1 : row + 2;

        for (int c = startCol; c <= endCol && !tooClose; c++) {
          for (int rg = startRow; rg <= endRow; rg++) {
            int neighborIdx = grid[c + rg * cols];
            if (neighborIdx != -1) {
              if (hypot(candidate.x - coords[neighborIdx].x, candidate.y - coords[neighborIdx].y) < r) {
                tooClose = true;
                break;
              }
            }
          }
        }

        if (!tooClose) {
          coords[seedsCount] = candidate;
          activeList[activeCount] = seedsCount;
          
          if (col >= 0 && col < cols && row >= 0 && row < rows) {
            grid[col + row * cols] = seedsCount;
          }
          
          seedsCount++;
          activeCount++;
          found = true;
          break; 
        }
      }
    }

    if (!found) {
      activeList[activeIdx] = activeList[activeCount - 1];
      activeCount--;
    }
  }

  // Shift X coordinate so they are [-width/2, width/2]
  for (int i = 0; i < nSeeds; i++) coords[i].x -= width / 2;

  delete[] grid;
  delete[] activeList;
}

/* Gaussian distribution random number using Box-Muller transformation with
 * the following twists:
 *	- all the samples are bounded within [mean*0.5, mean*1.5]
 *	- randomness control is used to adjust std. For instance,
 *	  RANDOMNESS=0.07803 for 80% of samples to fall within the center 20% of the range.
 *	            =0.09647 for 70%, =0.11882 for 60%, 0.14826 for 50%, ...
 */
float gRandom(float mean)
{
  bool negative = (mean < 0);
  if (negative) mean = -mean;
  float min = mean * 0.5;
  float max = mean * 1.5;
  float sd = RANDOMNESS * (max - min);
  float val = 0;
  do {
    // Two independent uniform random variables between 0 and 1
    float u1 = ran(1.0);
    if (u1 < 1e-9) u1 = 1e-9;
    float u2 = ran(1.0);

    // Box-Muller transform formula
    float z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    
    // Scale by standard deviation and shift by mean
    val = z0 * sd + mean;
  } while (val <  min || val > max); // cut off values outside the range
    
  return negative ? -val : val;
}

/* Uniform distribution random number ranging [min, max) */
float uRandom(float min, float max)
{
  return min + ran(max - min);
}

/* Get the coordinate of the contour at the given angle.
 */
V2f getContourCoord(int idContour, float angle)
{
  int ai = fmod(angle + 360.0, 360.0);  // map it to [0, 360)
  int vi = contours[idContour].angleToVertices[ai];
  return contours[idContour].vertices[vi];
}

/* Rotate a vector counterclockwise
 */
V2f rotateVector(V2f& vec, float degrees)
{
  // 1. Convert degrees to radians
  float radians = degrees * (M_PI / 180.0);
  float cosTheta = std::cos(radians);
  float sinTheta = std::sin(radians);

  // 2. Apply rotation formulas
  V2f rotated;
  rotated.x = vec.x * cosTheta - vec.y * sinTheta;
  rotated.y = vec.x * sinTheta + vec.y * cosTheta;

  return rotated;
}
