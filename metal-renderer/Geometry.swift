//
//  Geometry.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-30.
//

func subdivideClosedPolygon(polygon: [SIMD2<Float>], count: Int) -> [SIMD2<Float>]{
    if count == 0 {
        return polygon
    }
    var newVerts: [SIMD2<Float>] = Array(repeating: SIMD2<Float>(repeating: 0.0), count: 2 * polygon.count)
    newVerts.replaceSubrange(0..<polygon.count, with: polygon)
    for i in 0..<polygon.count{
        newVerts[2*i] = 0.75 * polygon[i] + 0.25 * polygon[(i + 1) % polygon.count]
        newVerts[2*i+1] = 0.25 * polygon[i] + 0.75 * polygon[(i + 1) % polygon.count]
    }
    return subdivideClosedPolygon(polygon: newVerts, count: count - 1)
}

