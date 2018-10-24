/*
Copyright (c) 2018 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.graphics.materials.bone;

import std.stdio;
import std.math;

import dlib.core.memory;
import dlib.math.vector;
import dlib.image.color;
import derelict.opengl;
import dagon.core.ownership;
import dagon.graphics.rc;
import dagon.graphics.material;
import dagon.graphics.materials.generic;
import dagon.resource.scene;

class BoneBackend: GLSLMaterialBackend
{
    string vsText =
    "
        #version 450 core

        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;
        uniform mat4 normalMatrix;

        uniform mat4 prevModelViewProjMatrix;
        uniform mat4 blurModelViewProjMatrix;

        layout (location = 0) in vec3 va_Vertex0;
        layout (location = 1) in vec3 va_Vertex1;
        layout (location = 2) in vec3 va_Vertex2;
        layout (location = 3) in vec3 va_Normal;
        layout (location = 4) in vec2 va_Texcoord;
        layout (location = 5) in uvec3 va_BoneIndices;
        layout (location = 6) in vec3 va_Weights;
        layout (location = 7) uniform mat4 pose[32];

        out vec2 texCoord;
        out vec3 eyePosition;
        out vec3 eyeNormal;

        out vec4 blurPosition;
        out vec4 prevPosition;

        void main()
        {
            texCoord = va_Texcoord;
            vec4 newNormal = pose[va_BoneIndices.x] * vec4(va_Normal, 0.0) * va_Weights.x
                           + pose[va_BoneIndices.y] * vec4(va_Normal, 0.0) * va_Weights.y
                           + pose[va_BoneIndices.z] * vec4(va_Normal, 0.0) * va_Weights.z;
            eyeNormal = (normalMatrix * newNormal).xyz;
            vec4 newVertex = pose[va_BoneIndices.x] * vec4(va_Vertex0, 1.0) * va_Weights.x
                           + pose[va_BoneIndices.y] * vec4(va_Vertex1, 1.0) * va_Weights.y
                           + pose[va_BoneIndices.z] * vec4(va_Vertex2, 1.0) * va_Weights.z;
            vec4 pos = modelViewMatrix * vec4(newVertex.xyz, 1.0);
            eyePosition = pos.xyz;

            vec4 position = projectionMatrix * pos;

            blurPosition = blurModelViewProjMatrix * vec4(newVertex.xyz, 1.0);
            prevPosition = prevModelViewProjMatrix * vec4(newVertex.xyz, 1.0);

            gl_Position = position;
        }
    ";

    string fsText =
    "
        #version 330 core

        uniform int layer;

        uniform sampler2D diffuseTexture;
        uniform sampler2D normalTexture;
        uniform sampler2D rmsTexture;
        uniform sampler2D emissionTexture;
        uniform float emissionEnergy;

        uniform int parallaxMethod;
        uniform float parallaxScale;
        uniform float parallaxBias;

        uniform float blurMask;

        in vec2 texCoord;
        in vec3 eyePosition;
        in vec3 eyeNormal;

        in vec4 blurPosition;
        in vec4 prevPosition;

        layout(location = 0) out vec4 frag_color;
        layout(location = 1) out vec4 frag_rms;
        layout(location = 2) out vec4 frag_position;
        layout(location = 3) out vec4 frag_normal;
        layout(location = 4) out vec4 frag_velocity;
        layout(location = 5) out vec4 frag_emission;

        mat3 cotangentFrame(in vec3 N, in vec3 p, in vec2 uv)
        {
            vec3 dp1 = dFdx(p);
            vec3 dp2 = dFdy(p);
            vec2 duv1 = dFdx(uv);
            vec2 duv2 = dFdy(uv);
            vec3 dp2perp = cross(dp2, N);
            vec3 dp1perp = cross(N, dp1);
            vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
            vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
            float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
            return mat3(T * invmax, B * invmax, N);
        }

        vec2 parallaxMapping(in vec3 V, in vec2 T, out float h)
        {
            float height = texture(normalTexture, T).a;
            h = height;
            height = height * parallaxScale + parallaxBias;
            return T + (height * V.xy);
        }

        void main()
        {
            vec3 E = normalize(-eyePosition);
            vec3 N = normalize(eyeNormal);
            mat3 TBN = cotangentFrame(N, eyePosition, texCoord);
            vec3 tE = normalize(E * TBN);

            vec2 posScreen = (blurPosition.xy / blurPosition.w) * 0.5 + 0.5;
            vec2 prevPosScreen = (prevPosition.xy / prevPosition.w) * 0.5 + 0.5;
            vec2 screenVelocity = posScreen - prevPosScreen;

            // Parallax mapping
            float height = 0.0;
            vec2 shiftedTexCoord = texCoord;
            if (parallaxMethod == 1)
                shiftedTexCoord = parallaxMapping(tE, texCoord, height);

            // Normal mapping
            vec3 tN = normalize(texture(normalTexture, shiftedTexCoord).rgb * 2.0 - 1.0);
            tN.y = -tN.y;
            N = normalize(TBN * tN);

            // Textures
            vec4 diffuseColor = texture(diffuseTexture, shiftedTexCoord);
            if (diffuseColor.a == 0)
                discard;
            vec4 rms = texture(rmsTexture, shiftedTexCoord);
            vec3 emission = texture(emissionTexture, shiftedTexCoord).rgb * emissionEnergy;

            float geomMask = float(layer > 0);

            frag_color = vec4(diffuseColor.rgb, geomMask);
            frag_rms = vec4(rms.r, rms.g, 1.0, 1.0);
            frag_position = vec4(eyePosition, geomMask);
            frag_normal = vec4(N, 1.0);
            frag_velocity = vec4(screenVelocity, 0.0, blurMask);
            frag_emission = vec4(emission, 1.0);
        }
    ";

    override string vertexShaderSrc() {return vsText;}
    override string fragmentShaderSrc() {return fsText;}

    GLint layerLoc;

    GLint modelViewMatrixLoc;
    GLint projectionMatrixLoc;
    GLint normalMatrixLoc;

    GLint prevModelViewProjMatrixLoc;
    GLint blurModelViewProjMatrixLoc;

    GLint diffuseTextureLoc;
    GLint normalTextureLoc;
    GLint rmsTextureLoc;
    GLint emissionTextureLoc;
    GLint emissionEnergyLoc;

    GLint parallaxMethodLoc;
    GLint parallaxScaleLoc;
    GLint parallaxBiasLoc;

    GLint blurMaskLoc;

    this(Owner o)
    {
        super(o);

        layerLoc = glGetUniformLocation(shaderProgram, "layer");

        modelViewMatrixLoc = glGetUniformLocation(shaderProgram, "modelViewMatrix");
        projectionMatrixLoc = glGetUniformLocation(shaderProgram, "projectionMatrix");
        normalMatrixLoc = glGetUniformLocation(shaderProgram, "normalMatrix");

        prevModelViewProjMatrixLoc = glGetUniformLocation(shaderProgram, "prevModelViewProjMatrix");
        blurModelViewProjMatrixLoc = glGetUniformLocation(shaderProgram, "blurModelViewProjMatrix");

        diffuseTextureLoc = glGetUniformLocation(shaderProgram, "diffuseTexture");
        normalTextureLoc = glGetUniformLocation(shaderProgram, "normalTexture");
        rmsTextureLoc = glGetUniformLocation(shaderProgram, "rmsTexture");
        emissionTextureLoc = glGetUniformLocation(shaderProgram, "emissionTexture");
        emissionEnergyLoc = glGetUniformLocation(shaderProgram, "emissionEnergy");

        parallaxMethodLoc = glGetUniformLocation(shaderProgram, "parallaxMethod");
        parallaxScaleLoc = glGetUniformLocation(shaderProgram, "parallaxScale");
        parallaxBiasLoc = glGetUniformLocation(shaderProgram, "parallaxBias");

        blurMaskLoc = glGetUniformLocation(shaderProgram, "blurMask");
    }

    override void bind(GenericMaterial mat, RenderingContext* rc)
    {
        auto idiffuse = "diffuse" in mat.inputs;
        auto inormal = "normal" in mat.inputs;
        auto iheight = "height" in mat.inputs;
        auto ipbr = "pbr" in mat.inputs;
        auto iroughness = "roughness" in mat.inputs;
        auto imetallic = "metallic" in mat.inputs;
        auto iemission = "emission" in mat.inputs;
        auto iEnergy = "energy" in mat.inputs;

        int parallaxMethod = intProp(mat, "parallax");
        if (parallaxMethod > ParallaxOcclusionMapping)
            parallaxMethod = ParallaxOcclusionMapping;
        if (parallaxMethod < 0)
            parallaxMethod = 0;

        glUseProgram(shaderProgram);

        glUniform1i(layerLoc, rc.layer);

        glUniform1f(blurMaskLoc, rc.blurMask);

        glUniformMatrix4fv(modelViewMatrixLoc, 1, GL_FALSE, rc.modelViewMatrix.arrayof.ptr);
        glUniformMatrix4fv(projectionMatrixLoc, 1, GL_FALSE, rc.projectionMatrix.arrayof.ptr);
        glUniformMatrix4fv(normalMatrixLoc, 1, GL_FALSE, rc.normalMatrix.arrayof.ptr);

        glUniformMatrix4fv(prevModelViewProjMatrixLoc, 1, GL_FALSE, rc.prevModelViewProjMatrix.arrayof.ptr);
        glUniformMatrix4fv(blurModelViewProjMatrixLoc, 1, GL_FALSE, rc.blurModelViewProjMatrix.arrayof.ptr);

        // Texture 0 - diffuse texture
        if (idiffuse.texture is null)
        {
            Color4f color = Color4f(idiffuse.asVector4f);
            idiffuse.texture = makeOnePixelTexture(mat, color);
        }
        glActiveTexture(GL_TEXTURE0);
        idiffuse.texture.bind();
        glUniform1i(diffuseTextureLoc, 0);

        // Texture 1 - normal map + parallax map
        float parallaxScale = 0.03f;
        float parallaxBias = -0.01f;
        bool normalTexturePrepared = inormal.texture !is null;
        if (normalTexturePrepared)
            normalTexturePrepared = inormal.texture.image.channels == 4;
        if (!normalTexturePrepared)
        {
            if (inormal.texture is null)
            {
                Color4f color = Color4f(0.5f, 0.5f, 1.0f, 0.0f); // default normal pointing upwards
                inormal.texture = makeOnePixelTexture(mat, color);
            }
            else
            {
                if (iheight.texture !is null)
                    packAlphaToTexture(inormal.texture, iheight.texture);
                else
                    packAlphaToTexture(inormal.texture, 0.0f);
            }
        }
        glActiveTexture(GL_TEXTURE1);
        inormal.texture.bind();
        glUniform1i(normalTextureLoc, 1);
        glUniform1f(parallaxScaleLoc, parallaxScale);
        glUniform1f(parallaxBiasLoc, parallaxBias);
        glUniform1i(parallaxMethodLoc, parallaxMethod);

        // Texture 2 - PBR maps (roughness + metallic)
        if (ipbr is null)
        {
            mat.setInput("pbr", 0.0f);
            ipbr = "pbr" in mat.inputs;
        }

        if (ipbr.texture is null)
        {
            ipbr.texture = makeTextureFrom(mat, *iroughness, *imetallic, materialInput(0.0f), materialInput(0.0f));
        }
        glActiveTexture(GL_TEXTURE2);
        glUniform1i(rmsTextureLoc, 2);
        ipbr.texture.bind();

        // Texture 3 - emission map
        if (iemission.texture is null)
        {
            Color4f color = Color4f(iemission.asVector4f);
            iemission.texture = makeOnePixelTexture(mat, color);
        }
        glActiveTexture(GL_TEXTURE3);
        iemission.texture.bind();
        glUniform1i(emissionTextureLoc, 3);
        glUniform1f(emissionEnergyLoc, iEnergy.asFloat);

        glActiveTexture(GL_TEXTURE0);
    }

    override void unbind(GenericMaterial mat, RenderingContext* rc)
    {
        auto idiffuse = "diffuse" in mat.inputs;
        auto inormal = "normal" in mat.inputs;
        auto ipbr = "pbr" in mat.inputs;
        auto iemission = "emission" in mat.inputs;

        glActiveTexture(GL_TEXTURE0);
        idiffuse.texture.unbind();

        glActiveTexture(GL_TEXTURE1);
        inormal.texture.unbind();

        glActiveTexture(GL_TEXTURE2);
        ipbr.texture.unbind();

        glActiveTexture(GL_TEXTURE3);
        iemission.texture.unbind();

        glActiveTexture(GL_TEXTURE0);

        glUseProgram(0);
    }
}
