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

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "include/CSShaderTypes.h"

// Vertex shader outputs and per-fragment inputs. Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment generated by clip-space primitives.
typedef struct
{
    // The [[position]] attribute qualifier of this member indicates this value is the clip space
    //   position of the vertex wen this structure is returned from the vertex shader
    float4 clipSpacePosition [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer will
    //   interpolate its value with values of other vertices making up the triangle and
    //   pass that interpolated value to the fragment shader for each fragment in that triangle;
    float2 textureCoordinate;

    // If no, then we fake an alpha value
    bool hasAlpha;
} RasterizerData;

// Vertex Function
vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant CSRenderVertex *vertexArray [[ buffer(CSRenderVertexInputIndexVertices) ]],
             constant vector_uint2 *viewportSizePointer  [[ buffer(CSRenderVertexInputIndexViewportSize) ]],
             constant matrix_float4x4 &transformation [[ buffer(CSRenderVertexInputIndexTransform) ]],
             constant bool *hasAlpha [[ buffer(CSRenderVertexInputIndexHasAlpha) ]])

{

    RasterizerData out;
    
    // Transform the vertex
    vector_float4 position = transformation * float4(vertexArray[vertexID].position,0,1);

    // Index into our array of positions to get the current vertex
    //   Our positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
    //   the origin)
    float2 pixelSpacePosition = position.xy;

    // Get the size of the drawable so that we can convert to normalized device coordinates,
    float2 viewportSize = float2(*viewportSizePointer);

    // The output position of every vertex shader is in clip space (also known as normalized device
    //   coordinate space, or NDC). A value of (-1.0, -1.0) in clip-space represents the
    //   lower-left corner of the viewport whereas (1.0, 1.0) represents the upper-right corner of
    //   the viewport.

    // In order to convert from positions in pixel space to positions in clip space we divide the
    //   pixel coordinates by half the size of the viewport.
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);

    // Set the z component of our clip space position 0 (since we're only rendering in
    //   2-Dimensions for this sample)
    out.clipSpacePosition.z = 0.0;

    // Set the w component to 1.0 since we don't need a perspective divide, which is also not
    //   necessary when rendering in 2-Dimensions
    out.clipSpacePosition.w = 1.0;

    // Pass our input textureCoordinate straight to our output RasterizerData. This value will be
    //   interpolated with the other textureCoordinate values in the vertices that make up the
    //   triangle.
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    
    // All fragments have alpha or not
    out.hasAlpha = *hasAlpha;

    return out;
}

// Fragment function
fragment float4
samplingShader(RasterizerData in [[stage_in]],
               texture2d<half> colorTexture [[ texture(CSRenderTextureIndexBaseColor) ]],
               sampler textureSampler [[ sampler(CSRenderSamplerIndexTexture) ]],
               constant bool *isInverted [[ buffer(CSRenderFragmentBufferIndexIsInverted) ]])
{
    // Sample the texture to obtain a color
    half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);

    // fake alpha
    if (!in.hasAlpha) {
        colorSample.a = 0xff;
    }

    // We return the color of the texture inverted when requested
    return float4(*isInverted ? colorSample.bgra : colorSample);
}

