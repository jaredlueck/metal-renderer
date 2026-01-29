//
//  ArrowGizmo.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-25.
//

import simd
import Metal

public struct ArrowGizmo {
    
    let rotation: simd_float4x4
    let color: SIMD3<Float>
    let device: MTLDevice

    init(device: MTLDevice, rotation: simd_float4x4, color: SIMD3<Float>){
        self.rotation = rotation
        self.color = color
        self.device = device
    }
    
    func computeArrowHeadVerticesCone(shaftLength: Float, headLength: Float, radius: Float) -> (vertices: [SIMD3<Float>], indices: [UInt16]) {
        let vertices: [SIMD3<Float>] = [
            // Circle center
            SIMD3<Float>(0, 0, shaftLength),
            //  Circle outline
            SIMD3<Float>(radius, 0, shaftLength),
            SIMD3<Float>(radius * cos(radians_from_degrees(45)), radius * sin(radians_from_degrees(45)), shaftLength),
            SIMD3<Float>(0, radius, shaftLength),
            SIMD3<Float>(-radius * cos(radians_from_degrees(45)), radius * sin(radians_from_degrees(45)), shaftLength),
            SIMD3<Float>(-radius, 0, shaftLength),
            SIMD3<Float>(-radius * cos(radians_from_degrees(45)), -radius * sin(radians_from_degrees(45)), shaftLength),
            SIMD3<Float>(0, -radius, shaftLength),
            SIMD3<Float>(radius * cos(radians_from_degrees(45)), -radius * sin(radians_from_degrees(45)), shaftLength),
            // tip
            SIMD3<Float>(0, 0, headLength + shaftLength),
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,  0, 2, 3,  0, 3, 4,  0, 4, 5,
            0, 5, 6,  0, 6, 7,  0, 7, 8,  0, 8, 1,

            1, 2, 9,  2, 3, 9,  3, 4, 9,  4, 5, 9,
            5, 6, 9,  6, 7, 9,  7, 8, 9,  8, 1, 9
        ]
        return (vertices: vertices, indices: indices)
    }
    
    func computeArrowHeadVerticesCube(shaftLength: Float, headLength: Float) -> (vertices: [SIMD3<Float>], indices: [UInt16]) {
        let halfW: Float = headLength * 0.5
        let halfH: Float = headLength * 0.5

        let z0: Float = shaftLength
        let z1: Float = shaftLength + headLength

        let p000 = SIMD3<Float>(-halfW, -halfH, z0) // x-, y-, z0
        let p100 = SIMD3<Float>( halfW, -halfH, z0) // x+, y-, z0
        let p110 = SIMD3<Float>( halfW,  halfH, z0) // x+, y+, z0
        let p010 = SIMD3<Float>(-halfW,  halfH, z0) // x-, y+, z0

        let p001 = SIMD3<Float>(-halfW, -halfH, z1) // x-, y-, z1
        let p101 = SIMD3<Float>( halfW, -halfH, z1) // x+, y-, z1
        let p111 = SIMD3<Float>( halfW,  halfH, z1) // x+, y+, z1
        let p011 = SIMD3<Float>(-halfW,  halfH, z1) // x-, y+, z1

        let vertices: [SIMD3<Float>] = [
            p001, p101, p111, p011,
            p000, p010, p110, p100,
            p101, p100, p110, p111,
            p001, p011, p010, p000,
            p011, p111, p110, p010,
            p001, p000, p100, p101
        ]

        let indices: [UInt16] = [
            0, 1, 2,  0, 2, 3,
            4, 5, 6,  4, 6, 7,
            8, 9,10,  8,10,11,
            12,13,14, 12,14,15,
            16,17,18, 16,18,19,
            20,21,22, 20,22,23
        ]
        return (vertices: vertices, indices: indices)
    }

    
    func computeArrowStemVertices(transform: matrix_float4x4, editorCamera: Camera , selected: Bool) -> (vertices: [SIMD3<Float>], indices: [UInt16]){
        let start = SIMD3<Float>(0.0, 0.0, 0.0)
        let end = SIMD3<Float>(0.0, 0.0, 1.0)
        
        let width = editorCamera.viewportSize.x
        let height = editorCamera.viewportSize.y
        
        let thickness: Float = selected ? 3.5 : 2.5
        
        let editorProjection = editorCamera.projectionMatrix
        let editorView = editorCamera.lookAtMatrix()
        
        let startClip = editorProjection * editorView * transform * SIMD4<Float>(start, 1.0)
        let endClip = editorProjection * editorView * transform * SIMD4<Float>(end, 1.0)
        
        let startNDC = SIMD3<Float>(startClip.x / startClip.w, startClip.y / startClip.w, startClip.z / startClip.w)
        let endNDC = SIMD3<Float>(endClip.x / endClip.w, endClip.y / endClip.w, endClip.z / endClip.w)
        
        let startPixel = SIMD2<Float>((startNDC[0] + 1) * (width/2), (startNDC[1] + 1) * (height/2))
        let endPixel = SIMD2<Float>((endNDC[0] + 1) * (width/2), (endNDC[1] + 1) * (height/2))
        
        // direction vector in pixel space
        let dir = endPixel - startPixel;
        // normal vector in pixel space is negative reciprocal
        let normal = simd_normalize(SIMD2(-dir[1], dir[0]));
        
        // expand the line segment in pixel space using the normal to compute new points of a quad
        let pEdge1 = startPixel + thickness * normal;
        let pEdge2 = startPixel - thickness * normal;
        let pEdge3 = endPixel + thickness * normal;
        let pEdge4 = endPixel - thickness * normal;
        
        // convert new points back to NDC
        let edge1NDC = SIMD4(2*(pEdge1[0]/width) - 1, 2*(pEdge1[1]/height) - 1, startNDC[2], 1.0);
        let edge2NDC = SIMD4(2*(pEdge2[0]/width) - 1, 2*(pEdge2[1]/height) - 1, startNDC[2], 1.0);
        let edge3NDC = SIMD4(2*(pEdge3[0]/width) - 1, 2*(pEdge3[1]/height) - 1, endNDC[2],   1.0);
        let edge4NDC = SIMD4(2*(pEdge4[0]/width) - 1, 2*(pEdge4[1]/height) - 1, endNDC[2],   1.0);
        
        // project back to world
        var edge1View = editorProjection.inverse * edge1NDC;
        edge1View /= edge1View.w;
        let edge1World = transform.inverse * editorView.inverse * edge1View;
        
        var edge2View = editorProjection.inverse * edge2NDC;
        edge2View /= edge2View.w;
        let edge2World = transform.inverse * editorView.inverse * edge2View;
        
        var edge3View = editorProjection.inverse * edge3NDC;
        edge3View /= edge3View.w;
        let edge3World = transform.inverse * editorView.inverse * edge3View;
        
        var edge4View = editorProjection.inverse * edge4NDC;
        edge4View /= edge4View.w;
        let edge4World = transform.inverse * editorView.inverse * edge4View;

        let outVertices: [SIMD3<Float>] = [
            edge1World[SIMD3<Int>(0,1,2)],
            edge2World[SIMD3<Int>(0,1,2)],
            edge3World[SIMD3<Int>(0,1,2)],
            edge3World[SIMD3<Int>(0,1,2)],
            edge2World[SIMD3<Int>(0,1,2)],
            edge4World[SIMD3<Int>(0,1,2)]
        ];

        return (vertices: outVertices, indices: [0, 1, 2, 3, 4, 5])
    }

    func encode(encoder: MTLRenderCommandEncoder, position: SIMD3<Float>, editorCamera: Camera, selected: Bool, transformMode: TransformMode) {
        encoder.pushDebugGroup("arrow gizmo")
        let radius: Float = 0.065
        let headLength: Float = 0.2
        let shaftLength: Float = 1.0
        let translation = matrix4x4_translation(position.x, position.y, position.z)
        let transform = translation * rotation
        let stemVertices = computeArrowStemVertices(transform: transform, editorCamera: editorCamera, selected: selected)
        let headVertices = transformMode == .translate ? computeArrowHeadVerticesCone(shaftLength: shaftLength, headLength: headLength, radius: radius) : computeArrowHeadVerticesCube(shaftLength: shaftLength, headLength: headLength)
                
        drawArrowGeometry(encoder: encoder, verts: stemVertices.vertices, indices: stemVertices.indices, transform: transform, color: color, selected: selected)
        drawArrowGeometry(encoder: encoder, verts: headVertices.vertices, indices: headVertices.indices, transform: transform, color: color, selected: selected)
        encoder.popDebugGroup()
    }
    
    func drawArrowGeometry(encoder: MTLRenderCommandEncoder, verts: [SIMD3<Float>], indices: [UInt16], transform: simd_float4x4, color: SIMD3<Float>, selected: Bool){
        let colorFactor: Float = selected ? 10 : 1.0
        var c = color * colorFactor
        
        guard let vbuf = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * verts.count, options: .storageModeShared) else { return }
        let vptr = vbuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: verts.count)
        for i in 0..<verts.count { vptr[i] = verts[i] }
        encoder.setVertexBuffer(vbuf, offset: 0, index: Int(BufferIndexVertex.rawValue))
 
        guard let instanceBuffer = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.stride, options: .storageModeShared) else { return }
        let iptr = instanceBuffer.contents().bindMemory(to: matrix_float4x4.self, capacity: 1)
        iptr[0] = transform
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: Int(BufferIndexInstanceData.rawValue))
        
        guard let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * indices.count, options: .storageModeShared) else { return }
        let indexPtr = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: indices.count)
        for i in 0..<indices.count { indexPtr[i] = indices[i] }

        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD3<Float>>.stride, index: Int(BufferIndexPipeline.rawValue))
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: MTLIndexType.uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        encoder.popDebugGroup()
    }
    
    func testArrowSelected(position: SIMD3<Float>, mouseX: Float, mouseY: Float, editorCamera: Camera) -> Bool {
        let translation = matrix4x4_translation(position.x, position.y, position.z)
        let transform = translation * rotation
        let width = editorCamera.viewportSize.x
        let height = editorCamera.viewportSize.y
    
        let head_center_z: Float = 1.1;
        
        let arrowBegin = SIMD3<Float>(0, 0, 0)
        let arrowEnd = SIMD3<Float>(0, 0, 1.0)
        
        // mouse in pixel space
        let pMouse = SIMD2<Float>(mouseX, mouseY)
        
        let arrowHead = SIMD3<Float>(0, 0, head_center_z)
        
        let mvp = editorCamera.projectionMatrix * editorCamera.lookAtMatrix() * transform
        
        var arrowHeadCenterNDC: SIMD4<Float> = mvp * SIMD4<Float>(0, 0, head_center_z, 1.0)
        arrowHeadCenterNDC /= arrowHeadCenterNDC.w
        let pArrowHeadCenter = SIMD2<Float>((arrowHeadCenterNDC[0] + 1.0) * (width/2.0), (arrowHeadCenterNDC[1] + 1.0) * (height/2.0))
        
        let arrowHeadSelectThreshold: Float = 8.0
        
        let distanceToArrowHead = distance(p1: pMouse, p2: pArrowHeadCenter)
        
        if distanceToArrowHead < arrowHeadSelectThreshold {
            return true
        }
        
        // project to pixel space
        var arrowBeginNDC = mvp  * SIMD4<Float>(arrowBegin, 1.0)
        var arrowEndNDC = mvp * SIMD4<Float>(arrowEnd, 1.0)
        var arrowHeadNDC = mvp * SIMD4<Float>(arrowHead, 1.0)
        
        arrowBeginNDC /= arrowBeginNDC.w
        arrowEndNDC /= arrowEndNDC.w
        arrowHeadNDC /= arrowHeadNDC.w
        // arrow start and end in pixel space
        let pArrowBegin = SIMD2<Float>((arrowBeginNDC[0] + 1.0) * (width/2.0), (arrowBeginNDC[1] + 1.0) * (height/2.0))
        let pArrowEnd = SIMD2<Float>((arrowEndNDC[0] + 1.0) * (width/2.0), (arrowEndNDC[1] + 1.0) * (height/2.0))
        let arrowLength = distance(p1: pArrowBegin, p2: pArrowEnd)
 
        // unit vector from the start to the end of the arrow stem
        let vArrowStem = normalize(pArrowEnd - pArrowBegin)
        // vector from the start point of the arrow to the mouse position
        let vArrowBeginMouse = SIMD2<Float>(mouseX, mouseY) - pArrowBegin
        // vector from the end point of the mouse to the mouse position
        let vArrowEndMouse = SIMD2<Float>(mouseX, mouseY) - pArrowEnd
        
        let distBegin = distance(p1: pArrowBegin, p2: pMouse)
        let distEnd = distance(p1: pArrowEnd, p2: pMouse)
        // projection of the vector from arrow start to the mouse onto the line segment
        let projBeg = dot(vArrowBeginMouse, vArrowStem)
        // projection of the vector from arrow end to the mouse onto the line segment
        let projEnd = dot(vArrowEndMouse, -vArrowStem)
        
        let stemSelectThreshold: Float = 5.0
        
        // The shortest distance from the mouse point to the stem is not on the line segment if the
        // projections from both sides of the segment are greater than the total length of the line segment
        if projBeg > arrowLength || projEnd > arrowLength{
            return min(distEnd, distBegin) < stemSelectThreshold
        }

        // the shortest distance is on the vector perpendicular from the mouse to the line segment
        return distance(p1: pArrowBegin, p2: pArrowEnd, x: pMouse) < stemSelectThreshold
    }
}

