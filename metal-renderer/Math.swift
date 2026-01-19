//
//  Math.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-07.
//

import simd

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix4x4_scale(scaleX: Float, scaleY: Float, scaleZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(scaleX, 0, 0, 0),
                                         vector_float4(0, scaleY, 0, 0),
                                         vector_float4(0, 0, scaleZ, 0),
                                         vector_float4(0, 0, 0, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func matrix_orthographic_right_hand(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    // nearZ and farZ are positive distances; camera looks down -Z.
    // This directly maps Z to [0, 1] for Metal.
    let rml = right - left
    let tmb = top - bottom
    let fn = farZ - nearZ

    let sx = 2.0 / rml
    let sy = 2.0 / tmb
    let sz = -1.0 / fn  // maps depth to [0,1] for Metal in RH

    let tx = -(right + left) / rml
    let ty = -(top + bottom) / tmb
    let tz = -nearZ / fn      // 0 at near, 1 at far

    return matrix_float4x4(columns: (
        SIMD4<Float>( sx,  0,  0, 0),
        SIMD4<Float>(  0, sy,  0, 0),
        SIMD4<Float>(  0,  0, sz, 0),
        SIMD4<Float>( tx, ty, tz, 1)
    ))
}

func matrix_lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    // basis vectors
    let zAxis = normalize(eye-target)
    let xAxis = normalize(cross(up, zAxis))
    let yAxis = cross(zAxis, xAxis)
    let translation = matrix4x4_translation(-eye.x, -eye.y, -eye.z)
    var result: matrix_float4x4 = matrix_identity_float4x4
    // orthonormal basis A^-1 = A^T
    result.columns.0 = SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0)
    result.columns.1 = SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0)
    result.columns.2 = SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0)
    return simd_mul(result, translation);
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

func gaussianKernel1D(size: Int, sigma: Float) -> [Float] {
    precondition(size > 0 && size % 2 == 1, "Kernel size should be a positive odd number")
    var kernel = Array(repeating: Float(0), count: size)
    let half = size / 2

    let twoSigma2 = 2.0 * sigma * sigma
    let norm: Float = 1.0 / sqrtf(2.0 * Float.pi * sigma * sigma)
    var sum: Float = 0

    for i in 0..<size {
        let x = Float(i - half)
        let exponent = -((x * x) / Float(twoSigma2))
        let value = norm * expf(exponent)
        kernel[i] = value
        sum += value
    }

    if sum != 0 {
        for i in 0..<size {
            kernel[i] /= sum
        }
    }
    return kernel
}
