//
//  SharedResources.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-08.
//
import Metal
import MetalKit
import simd

final class SharedResources{
    public var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    public var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    public var cameraPos: simd_float4 = .zero

    public var pointLights: [PointLight] = []
    public var pointLightShadowAtlas: MTLTexture
    public var lightCount: Int = 0

    public var outlineMask: MTLTexture?
    public var renderables: [InstancedRenderable] = []
    public var selectedRenderableInstance: Instance?
    public var colorBuffer: MTLTexture
    public var depthBuffer: MTLTexture
    public var skyBoxTexture: MTLTexture
    public var depthStencilStateDisabled: MTLDepthStencilState
    public var depthStencilStateEnabled: MTLDepthStencilState
    public var sampler: MTLSamplerState
    public var shadowSampler: MTLSamplerState
    public var view: MTKView
    
    public var colorTextureDescriptor: MTLTextureDescriptor
    public var maskTextureDescriptor: MTLTextureDescriptor
    public var depthTextureDescriptor: MTLTextureDescriptor

    init(
        device: MTLDevice,
         view: MTKView) {
             let size = view.drawableSize   // CGSize in pixels
             let width = Int(size.width)
             let height = Int(size.height)
    
        self.view = view
             let textureLoader = MTKTextureLoader(device: device)
             
             guard let url = Bundle.main.url(forResource: "vertical" , withExtension: "png") else {
                 fatalError("Couldn't find skybox texture")
             }
             let skyboxTexture = try! textureLoader.newTexture(URL: url, options: [.cubeLayout: MTKTextureLoader.CubeLayout.vertical])
             self.skyBoxTexture = skyboxTexture
             
             self.depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                 width: width,
                                                                 height: height,
                                                                 mipmapped: false)
             self.depthTextureDescriptor.storageMode = .private
             self.depthTextureDescriptor.usage = [.renderTarget]
             self.depthTextureDescriptor.textureType = .type2D
             let depthTexture = device.makeTexture(descriptor: self.depthTextureDescriptor)!
             self.depthBuffer = depthTexture
             
             let depthAttachmentDescriptor = MTLRenderPassDepthAttachmentDescriptor()
             depthAttachmentDescriptor.texture = depthTexture
             
             let shadowAtlasDesc = MTLTextureDescriptor()
             shadowAtlasDesc.textureType = .typeCubeArray
             shadowAtlasDesc.pixelFormat = .r32Float
             shadowAtlasDesc.width = width
             shadowAtlasDesc.height = height
             shadowAtlasDesc.arrayLength = 6
             shadowAtlasDesc.mipmapLevelCount = 1
             shadowAtlasDesc.sampleCount = 1
             shadowAtlasDesc.usage = [.renderTarget, .shaderRead]
             
             let shadowAtlas = device.makeTexture(descriptor: shadowAtlasDesc)!
             self.pointLightShadowAtlas = shadowAtlas
             
             self.colorTextureDescriptor = MTLTextureDescriptor()
             self.colorTextureDescriptor.textureType = .type2D
             self.colorTextureDescriptor.pixelFormat = view.colorPixelFormat
             self.colorTextureDescriptor.width = width
             self.colorTextureDescriptor.height = height
             self.colorTextureDescriptor.mipmapLevelCount = 1
             self.colorTextureDescriptor.usage = [.renderTarget, .shaderRead]
             
             let colorBuffer = device.makeTexture(descriptor: self.colorTextureDescriptor)!
             self.colorBuffer = colorBuffer
             
             self.maskTextureDescriptor = MTLTextureDescriptor()
             self.maskTextureDescriptor.textureType = .type2D
             self.maskTextureDescriptor.pixelFormat = .r32Float
             self.maskTextureDescriptor.height = height
             self.maskTextureDescriptor.width = width
             self.maskTextureDescriptor.usage = [.renderTarget, .shaderRead]
             
             let outlineMask = device.makeTexture(descriptor: self.maskTextureDescriptor)
             self.outlineMask = outlineMask
             
             let samplerDescriptor = MTLSamplerDescriptor()
             samplerDescriptor.minFilter = .linear
             samplerDescriptor.magFilter = .linear
             samplerDescriptor.mipFilter = .linear
             guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
                 fatalError("Failed to create sampler state")
             }
             self.sampler = sampler
             
             let shadowSamplerDesc = MTLSamplerDescriptor()
             shadowSamplerDesc.minFilter = .linear
             shadowSamplerDesc.magFilter = .linear
             shadowSamplerDesc.mipFilter = .notMipmapped // depth maps often no mipmaps
             shadowSamplerDesc.sAddressMode = .clampToEdge
             shadowSamplerDesc.tAddressMode = .clampToEdge
             shadowSamplerDesc.rAddressMode = .clampToEdge
             shadowSamplerDesc.normalizedCoordinates = true

             guard let shadowSampler = device.makeSamplerState(descriptor: shadowSamplerDesc) else {
                 fatalError("Failed to create shadow comparison sampler")
             }
             self.shadowSampler = shadowSampler
             let depthStencilStateDesabledDesc = MTLDepthStencilDescriptor()
             depthStencilStateDesabledDesc.isDepthWriteEnabled = false
             depthStencilStateDesabledDesc.depthCompareFunction = .always
             
             guard let depthStencilStateDisabled = device.makeDepthStencilState(descriptor: depthStencilStateDesabledDesc) else {
                 fatalError("Failed to create depth stencil state")
             }
             self.depthStencilStateDisabled = depthStencilStateDisabled
             
             let depthStencilStateEnabledDesc = MTLDepthStencilDescriptor()
             depthStencilStateEnabledDesc.isDepthWriteEnabled = true
             depthStencilStateEnabledDesc.depthCompareFunction = .lessEqual
             
             guard let depthStencilStateEnabled = device.makeDepthStencilState(descriptor: depthStencilStateEnabledDesc) else {
                 fatalError("Failed to create depth stencil state")
             }
             self.depthStencilStateEnabled = depthStencilStateEnabled
             
    }

    public func makeFrameUniforms() -> FrameUniforms {
        FrameUniforms(view: viewMatrix,
                      projection: projectionMatrix,
                      inverseView: viewMatrix.inverse,
                      inverseProjection: projectionMatrix.inverse,
                      cameraPos: cameraPos,
                      viewportSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)))
    }



    public func addPointLight(_ newValue: PointLight) {
        pointLights.append(newValue)
        lightCount = lightCount + 1
    }
}

