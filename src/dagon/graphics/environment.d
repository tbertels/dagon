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

module dagon.graphics.environment;

import dlib.core.memory;
import dlib.image.image;
import dlib.image.unmanaged;
import dlib.image.color;
import dlib.image.render.shapes;
import dlib.image.hsv;
import dlib.math.utils;
import dlib.math.vector;
import dlib.math.quaternion;
import dlib.math.interpolation;
import derelict.opengl;
import dagon.core.ownership;
import dagon.graphics.texture;

Color4f saturation(Color4f c, float s)
{
    ColorHSVAf hsv = ColorHSVAf(c);
    hsv.scaleSaturation(s);
    return hsv.rgba;
}

class Environment: Owner
{
    // TODO: change/interpolate parameters based on object position?
    
    bool useSkyColors = false;
    bool atmosphericFog = false;
    
    Color4f backgroundColor = Color4f(0.1f, 0.1f, 0.1f, 1.0f);
    Color4f ambientConstant = Color4f(0.1f, 0.1f, 0.1f, 1.0f);
    
    Texture environmentMap;    
    
	//Color4f sunZenithColor = Color4f(1.0, 0.9, 0.8, 1.0);
	//Color4f sunHorizonColor = Color4f(1.0, 0.2, 0.0, 1.0);
    Quaternionf sunRotation;
	float sunEnergy = 10.0f;//50.0f;
       
    Color4f skyZenithColorAtMidday = Color4f(0.1, 0.2, 1.0, 1.0);
    Color4f skyZenithColorAtSunset = Color4f(0.1, 0.2, 0.4, 1.0);
    Color4f skyZenithColorAtMidnight = Color4f(0.01, 0.01, 0.05, 1.0);
    
    Color4f skyHorizonColorAtMidday = Color4f(0.5, 0.6, 0.65, 1.0);
    Color4f skyHorizonColorAtSunset = Color4f(0.87, 0.44, 0.1, 1.0);
    Color4f skyHorizonColorAtMidnight = Color4f(0.1, 0.1, 0.1, 1.0);
    
    float skyEnergyAtMidday = 5.0;
    float skyEnergyAtSunset = 0.5;
    float skyEnergyAtMidnight = 0.001;
    
    Color4f groundColor = Color4f(0.5, 0.4, 0.4, 1.0);
    
    float groundEnergyAtMidday = 1.0;
    float groundEnergyAtSunset = 0.1;
    float groundEnergyAtMidnight = 0.0;
    
    Color4f fogColor = Color4f(0.1f, 0.1f, 0.1f, 1.0f);
    float fogStart = 0.0f;
    float fogEnd = 10000.0f;    
    //float fogEnergy = 0.1f;

    Color4f skyZenithColor = Color4f(0.223, 0.572, 0.752, 1.0);
    Color4f skyHorizonColor = Color4f(0.9, 1.0, 1.0, 1.0);
    float skyEnergy = 1.0f;
    float groundEnergy = 1.0f;
    
    bool showSun = true;
    bool showSunHalo = true;
    float sunSize = 1.0f;
    float sunScattering = 0.05f;

    this(Owner o)
    {
        super(o);
        
        sunRotation = rotationQuaternion(Axis.x, degtorad(-45.0f));
    }
    
    void update(double dt)
    { 
        if (useSkyColors)
        {
            skyZenithColor = lerpColorsBySunAngle(skyZenithColorAtMidday, skyZenithColorAtSunset, skyZenithColorAtMidnight);
            skyHorizonColor = lerpColorsBySunAngle(skyHorizonColorAtMidday, skyHorizonColorAtSunset, skyHorizonColorAtMidnight);
            backgroundColor = skyZenithColor;
            
            float s1 = clamp(dot(sunDirection, Vector3f(0.0, 1.0, 0.0)), 0.0, 1.0);
            float s2 = clamp(dot(sunDirection, Vector3f(0.0, -1.0, 0.0)), 0.0, 1.0);
            
            ambientConstant = (skyZenithColor + skyHorizonColor + Color4f(0.06f, 0.05f, 0.05f)) * 0.3f * lerp(lerp(0.01f, 0.001f, s2), 2.0f, s1);
             
            skyEnergy = lerp(lerp(skyEnergyAtSunset, skyEnergyAtMidnight, s2), skyEnergyAtMidday, s1);
            groundEnergy = lerp(lerp(groundEnergyAtSunset, groundEnergyAtMidnight, s2), groundEnergyAtMidday, s1);
            
            if (atmosphericFog)
                fogColor = skyHorizonColor * skyEnergy; //lerpColorsBySunAngle(skyZenithColor, skyHorizonColor, Color4f(0, 0, 0, 0)) * fogEnergy;
            else
                fogColor = backgroundColor;
        }
        else
        {
            fogColor = backgroundColor;
        }    
    }
    
    Vector3f sunDirection()
    {
        return sunRotation.rotate(Vector3f(0, 0, 1));
    }

	/+Color4f sunColor()
    {
	    return lerpColorsBySunAngle(sunZenithColor, sunHorizonColor, Color4f(0.0f, 0.0f, 0.0f, 1.0f));
    }+/
	Color4f sunColor=Color4f(1.0, 0.9, 0.8, 1.0);
    
    Color4f lerpColorsBySunAngle(Color4f atZenith, Color4f atHorizon, Color4f atNightSide)
    {
        float s = dot(sunDirection, Vector3f(0.0, 1.0, 0.0));
        Vector3f sunColor;
        if (s < 0.01f)
            sunColor = atNightSide;
        else if (s < 0.08f)
        {
            sunColor = lerp(atHorizon, atZenith, s);
            sunColor = lerp(sunColor, Vector3f(atNightSide), (0.07f - (s - 0.01f)) / 0.07f);
        }
        else
            sunColor = lerp(Vector3f(atHorizon), Vector3f(atZenith), s);
        return Color4f(sunColor.x, sunColor.y, sunColor.z, 1.0f);
    }
}
