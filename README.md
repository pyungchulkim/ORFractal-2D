# Ordered Random Fractal 2D (ORFractal-2D)

![ORFractal-2D screen shot](screen-shot.png)

<PRE>
--- extracted from lsystem.l ---
Ordered Random Fractal 2D (ORFractal-2D) Overview

This is an experimental art project designed to generate ordered randomness 
from arbitrary 2D shapes. Using fractal growth algorithms, I create self-similar forms 
that dynamically vary in scale and randomness. The core visual experience I aim to 
deliver is a sense of texture and rhythm crafted by nature over time - a visual 
manifestation of the principle of causality.

The project utilizes LPFG, an L-system fractal and simulation software developed at 
the University of Calgary. While I use 2D contours as source shapes, the canvas 
itself is a 3D drawing space, allowing for perspective views and complex layered 
geometries. This space is mapped as <x, y, z>, where the x-axis spans from left (-width/2) 
to right (width/2), the y-axis grows from bottom (0) to top (height), and the z-axis 
stretches from far back (-depth) to the foreground (0).

Within the program, each individual shape is denoted as a 'node.' Initial seeds are 
distributed inside a reference bounding box using a Poisson disk sampling algorithm, 
ensuring they are spread randomly without overlapping, mimicking natural spacing. 
I implement a genetic framework to dictate how these nodes evolve over time; a 'gene' 
is defined as a tuple containing the source contour paired with structural rules for 
fanout, pruning, rotation, and scaling. These source contours are designed within 
the 'contour' tab of L-studio, and their point vectors are used to scale and 
construct the nodes. By configuring distinct seed batches, I can control 
the number of initial nodes and the genetic behaviors governing their growth.

by Pyungchul Kim, 2026
https://orderedrandom.com

</PRE>

This program requires L-Studio to be installed. The following are steps for a quick start. It is based upon Windows 11, but it should work for other platforms.
1. Download files from this repository.
2. Download and install L-Studio from http://algorithmicbotany.org/virtual_laboratory/. I tested with L-studio ATE 4.4.1-2976 (July 13, 2016).
3. Start L-studio, select the menu "Object" --> "Open...", and locate the folder where this repository is downloaded.
4. In L-studio, select the menu "LPFG" --> "Go". It should launch a compiler and then output the image.
5. See L-Studio documentations (installed) to learn how to use it.

 
