//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#ifndef CSShaderTypes_h
#define CSShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum CSRenderVertexInputIndex
{
    CSRenderVertexInputIndexVertices     = 0,
    CSRenderVertexInputIndexViewportSize = 1,
    CSRenderVertexInputIndexTransform    = 2,
    CSRenderVertexInputIndexHasAlpha     = 3,
} CSRenderVertexInputIndex;

// Texture index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API texture set calls
typedef enum CSRenderTextureIndex
{
    CSRenderTextureIndexBaseColor = 0,
} CSRenderTextureIndex;

typedef enum CSRenderSamplerIndex
{
    CSRenderSamplerIndexTexture = 0,
} CSRenderSamplerIndex;

typedef enum CSRenderFragmentBufferIndex
{
    CSRenderFragmentBufferIndexIsInverted = 0,
} CSRenderFragmentBufferIndex;

//  This structure defines the layout of each vertex in the array of vertices set as an input to our
//    Metal vertex shader.  Since this header is shared between our .metal shader and C code,
//    we can be sure that the layout of the vertex array in the code matches the layout that
//    our vertex shader expects
typedef struct
{
    // Positions in pixel space (i.e. a value of 100 indicates 100 pixels from the origin/center)
    vector_float2 position;

    // 2D texture coordinate
    vector_float2 textureCoordinate;
} CSRenderVertex;

#endif /* CSShaderTypes_h */
