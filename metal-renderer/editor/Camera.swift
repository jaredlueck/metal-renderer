//
//  Camera.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-26.
//
import simd
import MetalKit

class Camera {
    public var position: SIMD3<Float>
    public var viewportSize: SIMD2<Float>
    
    public var projectionMatrix: simd_float4x4
    
    public var aspect: Float
    public var near: Float
    public var far: Float
    public var fov: Float
    
    
    init(position: SIMD3<Float>, viewportSize: SIMD2<Float>, fov: Float = 65, near: Float = 0.1, far: Float = 100.0){
        self.position = position
        self.viewportSize = viewportSize
        self.aspect = viewportSize.x / viewportSize.y
        self.near = near
        self.far = far
        self.fov = fov
        self.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(fov), aspectRatio: aspect, nearZ: near, farZ: far)
    }
    
    func lookAtMatrix() -> simd_float4x4 {
        return matrix_lookAt(eye: position, target: SIMD3(0, 0, 0), up:  SIMD3(0, 1, 0))
    }
    
    func updateProjection(drawableSize: CGSize){
        self.aspect = Float(drawableSize.width) / Float(drawableSize.height)
        self.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(fov), aspectRatio: aspect, nearZ: near, farZ: far)
    }
}
