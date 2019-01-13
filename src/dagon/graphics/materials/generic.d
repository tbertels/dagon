/*
Copyright (c) 2017-2018 Timur Gafarov

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

module dagon.graphics.materials.generic;

import std.stdio;
import std.algorithm;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.image.color;
import dlib.image.image;
import dlib.image.unmanaged;
import dlib.image.render.shapes;
import derelict.opengl;
import dagon.core.ownership;
import dagon.graphics.material;
import dagon.graphics.texture;
import dagon.graphics.rc;

interface GenericMaterialBackend
{
    final bool boolProp(GenericMaterial mat, string prop)
    {
        auto p = prop in mat.inputs;
        bool res = false;
        if (p.type == MaterialInputType.Bool ||
            p.type == MaterialInputType.Integer)
        {
            res = p.asBool;
        }
        return res;
    }

    final int intProp(GenericMaterial mat, string prop)
    {
        auto p = prop in mat.inputs;
        int res = 0;
        if (p.type == MaterialInputType.Bool ||
            p.type == MaterialInputType.Integer)
        {
            res = p.asInteger;
        }
        else if (p.type == MaterialInputType.Float)
        {
            res = cast(int)p.asFloat;
        }
        return res;
    }

    final Texture makeOnePixelTexture(Material mat, Color4f color)
    {
        auto img = New!UnmanagedImageRGBA8(8, 8);
        img.fillColor(color);
        auto tex = New!Texture(img, mat);
        return tex;
    }

    final void packAlphaToTexture(Texture rgb, Texture alpha)
    {
        SuperImage rgbaImg = New!UnmanagedImageRGBA8(rgb.width, rgb.height);
        foreach(y; 0..rgb.height)
        foreach(x; 0..rgb.width)
        {
            Color4f col = rgb.image[x, y];
            col.a = alpha.image[x, y].r;
            rgbaImg[x, y] = col;
        }

        rgb.release();
        rgb.createFromImage(rgbaImg);
    }

    final void packAlphaToTexture(Texture rgb, float alpha)
    {
        SuperImage rgbaImg = New!UnmanagedImageRGBA8(rgb.width, rgb.height);
        foreach(y; 0..rgb.height)
        foreach(x; 0..rgb.width)
        {
            Color4f col = rgb.image[x, y];
            col.a = alpha;
            rgbaImg[x, y] = col;
        }

        rgb.release();
        rgb.createFromImage(rgbaImg);
    }

    final Texture makeTextureFrom(Material mat, MaterialInput r, MaterialInput g, MaterialInput b, MaterialInput a)
    {
        uint width = 8;
        uint height = 8;

        if (r.texture !is null)
        {
            width = max(width, r.texture.width);
            height = max(height, r.texture.height);
        }

        if (g.texture !is null)
        {
            width = max(width, g.texture.width);
            height = max(height, g.texture.height);
        }

        if (b.texture !is null)
        {
            width = max(width, b.texture.width);
            height = max(height, b.texture.height);
        }

        if (a.texture !is null)
        {
            width = max(width, a.texture.width);
            height = max(height, a.texture.height);
        }

        SuperImage img = New!UnmanagedImageRGBA8(width, height);

        foreach(y; 0..img.height)
        foreach(x; 0..img.width)
        {
            Color4f col = Color4f(0, 0, 0, 0);

            float u = cast(float)x / cast(float)img.width;
            float v = cast(float)y / cast(float)img.height;

            col.r = r.sample(u, v).r;
            col.g = g.sample(u, v).r;
            col.b = b.sample(u, v).r;
            col.a = a.sample(u, v).r;

            img[x, y] = col;
        }

        auto tex = New!Texture(img, mat);
        return tex;
    }


    final void setTransformation(Vector3f position, Quaternionf rotation, RenderingContext* rc){
        import dlib.math.transformation;
        auto modelMatrix=translationMatrix(position)*rotation.toMatrix4x4;
        //auto invTransformation=rotation.inverse().toMatrix4x4*translationMatrix(-entity.position);
        setModelViewMatrix(rc.viewMatrix*modelMatrix);
    }
    final void setSpriteTransformation(Vector3f position, RenderingContext* rc){
        import dlib.math.transformation;
        import dlib.math.utils;
        setModelViewMatrix(rc.viewMatrix*translationMatrix(position)*rc.invViewRotationMatrix*rotationMatrix(Axis.x,degtorad(90.0f)));
    }
    void setModelViewMatrix(Matrix4x4f modelViewMatrix);


    void bind(GenericMaterial mat, RenderingContext* rc);
    void unbind(GenericMaterial mat, RenderingContext* rc);
}

enum int None = 0;

enum int ShadowFilterNone = 0;
enum int ShadowFilterPCF = 1;

enum int ParallaxNone = 0;
enum int ParallaxSimple = 1;
enum int ParallaxOcclusionMapping = 2;

enum int Opaque = 0;
enum int Transparent = 1;
enum int Additive = 2;

class GenericMaterial: Material
{
    protected GenericMaterialBackend _backend;

    this(GenericMaterialBackend backend, Owner o)
    {
        super(o);

        setInput("diffuse", Color4f(0.8f, 0.8f, 0.8f, 1.0f));
        setInput("specular", Color4f(1.0f, 1.0f, 1.0f, 1.0f));
        setInput("shadeless", false);
        setInput("emission", Color4f(0.0f, 0.0f, 0.0f, 1.0f));
        setInput("energy", 1.0f);
        setInput("transparency", 1.0f);
        setInput("roughness", 0.5f);
        setInput("metallic", 0.0f);
        setInput("normal", Vector3f(0.0f, 0.0f, 1.0f));
        setInput("height", 0.0f);
        setInput("parallax", ParallaxNone);
        setInput("parallaxScale", 0.03f);
        setInput("parallaxBias", -0.01f);
        setInput("shadowsEnabled", true);
        setInput("shadowFilter", ShadowFilterPCF);
        setInput("fogEnabled", true);
        setInput("blending", Opaque);
        setInput("culling", true);
        setInput("colorWrite", true);
        setInput("depthWrite", true);
        setInput("particleColor", Color4f(1.0f, 1.0f, 1.0f, 1.0f));
        setInput("particleSphericalNormal", false);

        _backend = backend;
    }

    GenericMaterialBackend backend()
    {
        return _backend;
    }

    void backend(GenericMaterialBackend b)
    {
        _backend = b;
    }

    bool isTransparent()
    {
        auto iblending = "blending" in inputs;
        int b = iblending.asInteger;
        return (b == Transparent || b == Additive);
    }

    override void bind(RenderingContext* rc)
    {
        auto iblending = "blending" in inputs;
        auto iculling = "culling" in inputs;
        auto icolorWrite = "colorWrite" in inputs;
        auto idepthWrite = "depthWrite" in inputs;

        if (iblending.asInteger == Transparent)
        {
            glEnablei(GL_BLEND, 0);
            glEnablei(GL_BLEND, 1);
            glBlendFunci(0, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glBlendFunci(1, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }
        else if (iblending.asInteger == Additive)
        {
            glEnablei(GL_BLEND, 0);
            glEnablei(GL_BLEND, 1);
            glBlendFunci(0, GL_SRC_ALPHA, GL_ONE);
            glBlendFunci(1, GL_SRC_ALPHA, GL_ONE);
        }

        if (iculling.asBool)
        {
            glEnable(GL_CULL_FACE);
        }

        if (!icolorWrite.asBool)
        {
            glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
        }

        if (!idepthWrite.asBool && !rc.shadowMode)
        {
            glDepthMask(GL_FALSE);
        }

        if (rc.overrideMaterialBackend)
            rc.overrideMaterialBackend.bind(this, rc);
        else if (_backend)
            _backend.bind(this, rc);
    }

    override void unbind(RenderingContext* rc)
    {
        auto icolorWrite = "colorWrite" in inputs;
        auto idepthWrite = "depthWrite" in inputs;

        if (rc.overrideMaterialBackend)
            rc.overrideMaterialBackend.unbind(this, rc);
        else if (_backend)
            _backend.unbind(this, rc);

        if (!idepthWrite.asBool && rc.depthPass)
        {
            glDepthMask(GL_TRUE);
        }

        if (!icolorWrite.asBool && rc.colorPass)
        {
            glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        }

        glDisable(GL_CULL_FACE);

        glDisablei(GL_BLEND, 0);
        glDisablei(GL_BLEND, 1);
    }
}

abstract class GLSLMaterialBackend: Owner, GenericMaterialBackend
{
    string vertexShaderSrc();
    string fragmentShaderSrc();

    GLuint shaderProgram;
    GLuint vertexShader;
    GLuint fragmentShader;

    this(Owner o)
    {
        super(o);

        const(char*)pvs = vertexShaderSrc().ptr;
        const(char*)pfs = fragmentShaderSrc().ptr;

        char[1000] infobuffer = 0;
        int infobufferlen = 0;

        vertexShader = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(vertexShader, 1, &pvs, null);
        glCompileShader(vertexShader);
        GLint success = 0;
        glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &success);
        if (!success)
        {
            GLint logSize = 0;
            glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logSize);
            glGetShaderInfoLog(vertexShader, 999, &logSize, infobuffer.ptr);
            writeln("Error in vertex shader:");
            writeln(infobuffer[0..logSize]);
        }

        fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragmentShader, 1, &pfs, null);
        glCompileShader(fragmentShader);
        success = 0;
        glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &success);
        if (!success)
        {
            GLint logSize = 0;
            glGetShaderiv(fragmentShader, GL_INFO_LOG_LENGTH, &logSize);
            glGetShaderInfoLog(fragmentShader, 999, &logSize, infobuffer.ptr);
            writeln("Error in fragment shader:");
            writeln(infobuffer[0..logSize]);
         }

        shaderProgram = glCreateProgram();
        glAttachShader(shaderProgram, vertexShader);
        glAttachShader(shaderProgram, fragmentShader);
        glLinkProgram(shaderProgram);
    }

    void bind(GenericMaterial mat, RenderingContext* rc)
    {
        glUseProgram(shaderProgram);
    }

    void unbind(GenericMaterial mat, RenderingContext* rc)
    {
        glUseProgram(0);
    }
}
