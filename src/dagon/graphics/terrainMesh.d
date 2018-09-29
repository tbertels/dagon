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

module dagon.graphics.terrainMesh;

import dlib.core.memory;
import dlib.geometry.triangle;
import dlib.math.vector;
import derelict.opengl;
import dagon.core.interfaces;
import dagon.core.ownership;

enum VertexAttrib
{
    Vertices = 0,
    Normals = 1,
    Texcoords = 2,
    Texture = 3,
    DetailTexture = 4
}

class TerrainMesh: Owner, Drawable
{
    bool dataReady = false;
    bool canRender = false;
    
    // TODO: make these DynamicArrays
    Vector3f[] vertices;
    Vector3f[] normals;
    Vector2f[] texcoords;
	uint[3][] indices;
	uint[] textures;
	uint[] detailTextures;
    
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint nbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;
	GLuint txo = 0;
	GLuint dto = 0;
    
    this(Owner o)
    {
        super(o);
    }
    
    ~this()
    {
        if (vertices.length) Delete(vertices);
        if (normals.length) Delete(normals);
        if (texcoords.length) Delete(texcoords);
        if (textures.length) Delete(textures);
        if (indices.length) Delete(indices);
        
        if (canRender)
        {
            glDeleteVertexArrays(1, &vao);
            glDeleteBuffers(1, &vbo);
            glDeleteBuffers(1, &nbo);
            glDeleteBuffers(1, &tbo);
            glDeleteBuffers(1, &eao);
        }
    }
    
    int opApply(scope int delegate(Triangle t) dg)
    {
        int result = 0;

        foreach(i, ref f; indices)
        {
            Triangle tri;

            tri.v[0] = vertices[f[0]];
            tri.v[1] = vertices[f[1]];
            tri.v[2] = vertices[f[2]];
            tri.n[0] = normals[f[0]];
            tri.n[1] = normals[f[1]];
            tri.n[2] = normals[f[2]];
            tri.t1[0] = texcoords[f[0]];
            tri.t1[1] = texcoords[f[1]];
            tri.t1[2] = texcoords[f[2]];
            tri.normal = (tri.n[0] + tri.n[1] + tri.n[2]) / 3.0f;

            result = dg(tri);
            if (result)
                break;
        }

        return result;
    }
    
    void generateNormals()
    {
        if (normals.length == 0)
            return;
    
        normals[] = Vector3f(0.0f, 0.0f, 0.0f);
    
        foreach(i, ref f; indices)
        {
            Vector3f v0 = vertices[f[0]];
            Vector3f v1 = vertices[f[1]];
            Vector3f v2 = vertices[f[2]];
            
            Vector3f p = cross(v1 - v0, v2 - v0);
            
            normals[f[0]] += p;
            normals[f[1]] += p;
            normals[f[2]] += p;
        }
        
        foreach(i, n; normals)
        {
            normals[i] = n.normalized;
        }
    }
    
    void prepareVAO()
    {
        if (!dataReady)
            return;

        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 3, vertices.ptr, GL_STATIC_DRAW); 

        glGenBuffers(1, &nbo);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glBufferData(GL_ARRAY_BUFFER, normals.length * float.sizeof * 3, normals.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);
        
        glGenBuffers(1, &txo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, txo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, textures.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &dto);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dto);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, detailTextures.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);
        
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
    
        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, 3, GL_FLOAT, GL_FALSE, 0, null);
    
        glEnableVertexAttribArray(VertexAttrib.Normals);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glVertexAttribPointer(VertexAttrib.Normals, 3, GL_FLOAT, GL_FALSE, 0, null);
    
        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, 2, GL_FLOAT, GL_FALSE, 0, null);

        glEnableVertexAttribArray(VertexAttrib.Texture);
        glBindBuffer(GL_ARRAY_BUFFER, txo);
        glVertexAttribPointer(VertexAttrib.Texture, 1, GL_INT, GL_FALSE, 0, null);

        glEnableVertexAttribArray(VertexAttrib.DetailTexture);
        glBindBuffer(GL_ARRAY_BUFFER, dto);
        glVertexAttribPointer(VertexAttrib.Texture, 1, GL_INT, GL_FALSE, 0, null);

        glBindVertexArray(0);
        
        canRender = true;
    }
    
    void update(double dt)
    {
    }
    
    void render(RenderingContext* rc)
    {
        if (canRender)
        {
            glBindVertexArray(vao);
            glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
            glBindVertexArray(0);
        }
    }
}

