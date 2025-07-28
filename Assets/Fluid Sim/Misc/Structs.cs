using System;
using UnityEngine;


public struct Particle3D
{
    public Vector3 position;
    public Vector3 velocity;
    public float radius;

    public Vector3 predictedPosition;

    public float density;
    public float nearDensity;
}


public struct Particle2D
{
    public Vector2 position;
    public Vector2 velocity;
    public float radius;

    public Vector2 predictedPosition;

    public float density;
    public float nearDensity;
}

public struct Entry : IComparable<Entry>
{
    public Entry(uint particleIndex, uint hash, uint cellKey)
    {
        this.particleIndex = particleIndex;
        this.hash = hash;
        this.cellKey = cellKey;
    }

    public uint particleIndex;
    public uint hash;
    public uint cellKey;

    public int CompareTo(Entry other)
    {
        // Example: Sort by cellKey, then particleIndex
        int cellComparison = this.cellKey.CompareTo(other.cellKey);
        if (cellComparison != 0) return cellComparison;
        return 0;
        //return this.particleIndex.CompareTo(other.particleIndex);
    }
};



